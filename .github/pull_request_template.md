## Describe your changes

<!-- Describe your changes in detail -->

## Checklist before requesting a review
- [ ] Chart version bumped (`Chart.yaml`) <!-- Respect proper [semver](https://semver.org)  -->
- [ ] Values schema updated (`values.schema.json`) <!-- Chart installation/templating will fail if not changed at deploy time, add a Unit or CI Test to ensure your changes work end to end -->
- [ ] Changes updated in [ArtifactHub syntax](https://artifacthub.io/docs/topics/annotations/helm) (`Chart.yaml`) <!-- Changes are incremental, delete all previous changes and don't repeat the change type in the message -->
- [ ] Pre-Commit passed or has been run manually (`Makefile`)
