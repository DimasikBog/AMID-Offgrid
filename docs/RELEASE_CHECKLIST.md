# Publication gates

All boxes concern the final candidate, not an earlier build.

- [ ] Final source commit has clean checks, verified artifacts and provenance.
- [ ] All required functions from the original services list have explicit acceptance results.
- [ ] Physical Android and iPhone checks in TEST_MATRIX.md have passed.
- [ ] Permanent Android identity and upgrade/backup migration have been verified.
- [ ] Apple signing/provisioning and personal iPhone install have been verified.
- [ ] No unresolved data-loss defect or release-blocking vulnerability remains.
- [ ] License notices, publisher contact, privacy URL, icons and real screenshots are complete.
- [ ] Store descriptions promise only actually implemented, tested features.

## App Store

- [ ] Active authorized developer membership/publisher, agreements and Bundle ID.
- [ ] Signed IPA, correct profile/entitlements and a unique build number.
- [ ] Xcode/iOS SDK meet the requirements on the submission date (currently 26+).
- [ ] Final TestFlight/device acceptance, age rating, App Privacy and applicable encryption answers.
- [ ] App Store Connect validation; App Review approval and actual release recorded separately.

## Google Play

- [ ] Final AAB has a validated install-time AI pack and passes offline split-install tests ([procedure](PLAY_DELIVERY.md)).
- [ ] Verified Play Console account and any applicable registration/device requirements.
- [ ] Upload-key-signed AAB, Play App Signing and target API requirements met (currently API 36 for new apps/updates).
- [ ] 64-bit/16 KiB library compatibility and real-device acceptance.
- [ ] Internal test and, where applicable, 12 continuously opted-in testers for 14 days, then production-access approval.
- [ ] Data safety, content rating, audience and permission declarations match behavior.
- [ ] Console validation, review approval and actual release recorded separately.

Payments have not been authorized. Missing memberships, publisher decisions or
signing keys stay open even when the app compiles. Recheck requirements using
the official links on the AMID App planning Page before submission.
