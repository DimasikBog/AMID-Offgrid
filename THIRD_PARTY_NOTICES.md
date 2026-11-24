# Third-party notices

The app is an independent implementation. It does not include the apps,
accounts or messaging protocols of Kiwix, Organic Maps, PocketPal, Briar or
BitChat. Do not claim affiliation or interoperability without a separate tested
integration and applicable permissions/licenses.

- Flutter and Dart: retain the license notices distributed with their SDKs.
- Pub dependencies: versions and hosted-package digests are recorded in
  pubspec.lock. The app's «Ліцензії компонентів» screen exposes registered
  Flutter/plugin notices. Native transitive libraries also require review.
- Natural Earth world geometry in assets/world.geojson: public domain,
  https://www.naturalearthdata.com/about/terms-of-use/ .
- Optional Qwen3-0.6B-GGUF download: Qwen Team, Apache-2.0; pinned revision and
  SHA-256 in ImportService. The model is downloaded separately, not bundled.
  https://huggingface.co/Qwen/Qwen3-0.6B-GGUF .
- User-imported texts, maps and models retain their original licenses. A file's
  presence or ability to import it does not grant redistribution rights.

AMID application code is available under the MIT license in LICENSE, as
authorized by the owner for this open-source release. This grant does not
relicense Flutter, Gradle, plugins, native dependencies, Natural Earth or
user-imported materials. Their original terms and notices continue to apply.
Before store publication audit the complete native dependency notices and
attribution requirements against the final built artifacts.
