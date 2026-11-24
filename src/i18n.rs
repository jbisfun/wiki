//! Site languages. The first locale is the source language (English) at the
//! site root; every other one is a full copy of the site under its own prefix
//! (`zh-TW` -> `zh-tw/`). The chrome comes from Fluent files
//! (`locales/<tag>/*.ftl`, through fluent-templates); repo pages are
//! machine-translated (see [`crate::translate`]).
use std::borrow::Cow;
use std::collections::HashMap;
use std::fs;
use std::sync::Arc;

use anyhow::{Context, Result, anyhow};
use fluent_templates::fluent_bundle::FluentValue;
use fluent_templates::{ArcLoader, LanguageIdentifier, Loader};
use minijinja::value::{Kwargs, Value};
use serde::{Deserialize, Serialize};

use crate::Paths;
use crate::state;
use crate::translate::TranslatorConfig;

/// wiki.toml `[i18n]`.
#[derive(Deserialize, Serialize, Default)]
#[serde(default)]
pub struct I18nConfig {
    /// Languages besides English, as BCP 47 tags with a `locales/<tag>/` folder.
    pub locales: Vec<String>,
    pub translator: TranslatorConfig,
}

pub struct Locale {
    pub tag: String,
    pub lang: LanguageIdentifier,
    /// Output path prefix: "" for the source language, else "<tag lowercased>/".
    pub prefix: String,
}

impl Locale {
    fn new(tag: &str, source: bool) -> Result<Self> {
        let lang = tag.parse().map_err(|err| anyhow!("locale {tag}: {err}"))?;
        let prefix = if source { String::new() } else { format!("{}/", tag.to_lowercase()) };
        Ok(Self { tag: tag.to_owned(), lang, prefix })
    }

    pub fn is_source(&self) -> bool {
        self.prefix.is_empty()
    }
}

pub struct I18n {
    /// The source language first.
    pub locales: Vec<Locale>,
    pub config: I18nConfig,
    loader: Arc<ArcLoader>,
}

#[derive(Deserialize)]
struct WikiToml {
    #[serde(default)]
    i18n: I18nConfig,
}

pub const SOURCE: &str = "en";

impl I18n {
    pub fn load(paths: &Paths) -> Result<Self> {
        let toml_path = paths.wiki.join("wiki.toml");
        let config = toml::from_str::<WikiToml>(&fs::read_to_string(&toml_path)?)
            .with_context(|| format!("parsing {}", toml_path.display()))?
            .i18n;
        let mut locales = vec![Locale::new(SOURCE, true)?];
        for tag in &config.locales {
            locales.push(Locale::new(tag, false)?);
        }
        let loader = ArcLoader::builder(&paths.wiki.join("locales"), locales[0].lang.clone())
            // Fluent wraps placeables in Unicode isolation marks; HTML doesn't need them.
            .customize(|bundle| bundle.set_use_isolating(false))
            .build()
            .map_err(|err| anyhow!("loading locales/: {err}"))?;
        Ok(Self { locales, config, loader: Arc::new(loader) })
    }

    pub fn source(&self) -> &Locale {
        &self.locales[0]
    }

    pub fn t(&self, locale: &Locale, key: &str) -> String {
        self.loader.lookup(&locale.lang, key)
    }

    /// Everything every page of every language depends on: the Fluent files and the locale list.
    pub fn input_ids(&self, paths: &Paths) -> Vec<String> {
        let mut ids = state::dir_ids(&paths.wiki.join("locales"));
        ids.push(self.config.locales.join(","));
        ids
    }

    /// The template function `t(key, **args)`.
    pub fn function(&self, locale: &Locale) -> Value {
        let loader = self.loader.clone();
        let lang = locale.lang.clone();
        Value::from_function(move |key: String, kwargs: Kwargs| -> Result<String, minijinja::Error> {
            let mut args: HashMap<Cow<'static, str>, FluentValue> = HashMap::new();
            for name in kwargs.args() {
                let value: Value = kwargs.get(name)?;
                let value = match f64::try_from(value.clone()) {
                    Ok(number) if value.is_number() => FluentValue::from(number),
                    _ => FluentValue::from(value.to_string()),
                };
                args.insert(Cow::Owned(name.to_owned()), value);
            }
            Ok(loader.lookup_complete(&lang, &key, Some(&args)))
        })
    }
}
