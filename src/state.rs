//! What needs regenerating, decided with git object ids.
//!
//! Every input is identified the way git identifies it: files by their blob id
//! (`git hash-object`), a repo's sources by its HEAD tree id plus the patch id
//! of its uncommitted changes. A unit of work (a repo's pages, a code
//! reference, the asset bundle) gets a key hashed from the ids of its inputs;
//! `.build/state.json` keeps the key each unit was last built with, and a
//! unit whose key is unchanged is left alone.
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use anyhow::Result;
use git2::{DiffOptions, ObjectType, Oid, Repository};
use serde::{Deserialize, Serialize};

use crate::apidoc::Api;

#[derive(Default, Serialize, Deserialize)]
pub struct State {
    /// Key of everything every page depends on (templates, nav, the wiki binary).
    #[serde(default)]
    pub global: String,
    #[serde(default)]
    pub assets: String,
    /// Repo name -> key of its rendered pages under dist/<repo>.
    #[serde(default)]
    pub repos: BTreeMap<String, String>,
    /// "<repo>/<tool>" -> code reference built with that key.
    #[serde(default)]
    pub apidoc: BTreeMap<String, ApiState>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct ApiState {
    pub key: String,
    pub entries: Vec<Api>,
}

impl State {
    pub fn load(build: &Path) -> Self {
        fs::read(build.join("state.json"))
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, build: &Path) -> Result<()> {
        fs::create_dir_all(build)?;
        fs::write(build.join("state.json"), serde_json::to_vec_pretty(self)?)?;
        Ok(())
    }
}

/// Blob id of a byte string (`git hash-object --stdin`); joins several parts.
pub fn key<S: AsRef<str>>(parts: impl IntoIterator<Item = S>) -> String {
    let mut bytes = Vec::new();
    for part in parts {
        bytes.extend_from_slice(part.as_ref().as_bytes());
        bytes.push(0);
    }
    Oid::hash_object(ObjectType::Blob, &bytes).map(|oid| oid.to_string()).unwrap_or_default()
}

/// Blob id of a file (`git hash-object FILE`); empty when it can't be read.
pub fn file_id(path: &Path) -> String {
    Oid::hash_file(ObjectType::Blob, path).map(|oid| oid.to_string()).unwrap_or_default()
}

/// Blob id of a text (`git hash-object` of a file with this content).
pub fn text_id(text: &str) -> String {
    Oid::hash_object(ObjectType::Blob, text.as_bytes()).map(|oid| oid.to_string()).unwrap_or_default()
}

/// Blob ids of every file under `dir`, as "relative path\0id" parts.
pub fn dir_ids(dir: &Path) -> Vec<String> {
    let mut parts: Vec<String> = walkdir::WalkDir::new(dir)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| {
            let rel = entry.path().strip_prefix(dir).unwrap_or(entry.path());
            format!("{}\0{}", rel.display(), file_id(entry.path()))
        })
        .collect();
    parts.sort();
    parts
}

/// Id of a repo's current sources: HEAD's tree id plus the patch id of
/// everything uncommitted (staged, unstaged and untracked).
pub fn source_id(path: &Path) -> Result<String> {
    let repo = Repository::open(path)?;
    let tree = repo.head().ok().and_then(|head| head.peel_to_tree().ok());
    let mut options = DiffOptions::new();
    options.include_untracked(true).recurse_untracked_dirs(true).show_untracked_content(true);
    let diff = repo.diff_tree_to_workdir_with_index(tree.as_ref(), Some(&mut options))?;
    let tree_id = tree.map(|tree| tree.id().to_string()).unwrap_or_default();
    let patch_id = if diff.deltas().len() == 0 { String::new() } else { diff.patchid(None)?.to_string() };
    Ok(key([tree_id, patch_id]))
}
