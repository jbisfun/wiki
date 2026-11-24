//! `wiki`: one static site from every repo in a pull workspace.
//!
//! Each repo's README is its entry page, its `docs/` folder becomes pages, and
//! rustdoc / LDoc / JSDoc produce its code reference. Git object ids (blob,
//! tree and patch ids) decide what has to be regenerated: see [`state`].
mod apidoc;
mod bundle;
mod collect;
mod i18n;
mod markdown;
mod render;
mod state;
mod translate;

use std::path::{Path, PathBuf};
use std::{env, fs};

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(version, about = "Static wiki from every repo in a pull workspace")]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Build the site into dist/, regenerating only what changed.
    Build {
        /// Ignore .build/state.json and rebuild everything.
        #[arg(long)]
        force: bool,
    },
    /// Build, then mirror dist/ into the Pages repo and stage it.
    Publish {
        #[arg(long)]
        force: bool,
    },
    /// Remove .build and dist.
    Clean,
}

/// Paths of one run.
pub struct Paths {
    /// The wiki repo: wiki.toml, templates/, pages/, assets/.
    pub wiki: PathBuf,
    /// The pull workspace root.
    pub root: PathBuf,
    /// .build: state.json and the code reference per repo.
    pub build: PathBuf,
    pub dist: PathBuf,
}

impl Paths {
    fn find() -> Result<Self> {
        let cwd = env::current_dir()?;
        let pull_root = env::var_os("PULL_ROOT").map(PathBuf::from);
        let wiki = match cwd.ancestors().find(|dir| dir.join("wiki.toml").is_file()) {
            Some(dir) => dir.to_path_buf(),
            None => match &pull_root {
                Some(root) if root.join("wiki/wiki.toml").is_file() => root.join("wiki"),
                _ => bail!("no wiki.toml above {} and none in $PULL_ROOT/wiki", cwd.display()),
            },
        };
        let root = match pull_root {
            Some(root) => root,
            None => wiki.parent().context("the wiki repo has no parent dir")?.to_path_buf(),
        };
        Ok(Self { build: wiki.join(".build"), dist: wiki.join("dist"), wiki, root })
    }
}

pub fn warn(message: impl std::fmt::Display) {
    eprintln!("wiki: {message}");
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let paths = Paths::find()?;
    match cli.command.unwrap_or(Command::Build { force: false }) {
        Command::Build { force } => build(&paths, force),
        Command::Publish { force } => {
            build(&paths, force)?;
            publish(&paths)
        }
        Command::Clean => {
            for dir in [&paths.build, &paths.dist] {
                if dir.exists() {
                    fs::remove_dir_all(dir)?;
                }
            }
            Ok(())
        }
    }
}

fn build(paths: &Paths, force: bool) -> Result<()> {
    let mut state = if force { state::State::default() } else { state::State::load(&paths.build) };
    let repos = collect::collect(paths)?;
    let apis = apidoc::generate(paths, &repos, &mut state)?;
    bundle::bundle(paths, &mut state)?;
    render::render(paths, &repos, &apis, &mut state)?;
    state.save(&paths.build)
}

/// Mirror dist/ into the GitHub Pages repo and stage it, so the pull precommit
/// hook lands the site in the same `pull commit`.
fn publish(paths: &Paths) -> Result<()> {
    let target = env::var_os("WIKI_PUBLISH_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| paths.root.join("jbisfun.github.io"));
    let status = std::process::Command::new("rsync")
        .args(["-a", "--delete", "--exclude", ".git", "--exclude", "CNAME", "--exclude", "README.md"])
        .arg(format!("{}/", paths.dist.display()))
        .arg(format!("{}/", target.display()))
        .status()
        .context("running rsync")?;
    if !status.success() {
        bail!("rsync into {} failed", target.display());
    }
    fs::write(target.join(".nojekyll"), "")?;
    let staged = stage_all(&target)?;
    println!("wiki: published to {} ({staged} files staged)", target.display());
    Ok(())
}

/// `git add -A` in `dir`; returns how many files differ from HEAD in the index.
fn stage_all(dir: &Path) -> Result<usize> {
    let repo = git2::Repository::open(dir).with_context(|| format!("opening {}", dir.display()))?;
    let mut index = repo.index()?;
    index.add_all(["*"], git2::IndexAddOption::DEFAULT, None)?;
    index.update_all(["*"], None)?;
    index.write()?;
    let head = repo.head().ok().and_then(|head| head.peel_to_tree().ok());
    Ok(repo.diff_tree_to_index(head.as_ref(), Some(&index), None)?.deltas().len())
}
