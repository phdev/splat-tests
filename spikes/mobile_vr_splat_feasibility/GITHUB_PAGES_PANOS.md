# GitHub Pages Panos

licensed research asset; production usage depends on 360Cities license terms.

## Status

- Status: `packaged`
- Generated: `2026-07-02T23:02:32Z`
- Site dir: `docs` (existing ./docs)
- Panos page: `docs/panos/index.html`
- Pano manifest: `docs/panos/panos.json`
- Full-res included: `false`
- Main-nav handling: `panos_link_already_present` in `docs/index.html`

## Source Pano Selected

- Primary source type: `people_removed`
- Primary source path: `assets/machu_picchu_panoramas/360cities_machu_picchu/cleaned/360cities_machu_picchu_people_removed_equirect.jpg`
- Original source path: `assets/machu_picchu_panoramas/360cities_machu_picchu/original/360cities_machu_picchu_equirect.jpg`
- Cleaned source path: `assets/machu_picchu_panoramas/360cities_machu_picchu/cleaned/360cities_machu_picchu_people_removed_equirect.jpg`
- Source URL: `https://www.360cities.net/image/machu-picchu`
- Photographer: `Julius Sunpanoramas.com`
- License note: `360Cities XML metadata: licensed=True, licenseable=True; user provided separate license note for local research scrape; confirm production usage separately.`

## Generated Preview Paths

- Primary 4096 preview: `docs/panos/assets/machu_picchu_pano_4096x2048.jpg`
- Primary 2048 preview: `docs/panos/assets/machu_picchu_pano_2048x1024.jpg`
- Primary thumbnail: `docs/panos/assets/thumbnail.jpg`
- Original 4096 preview: `docs/panos/assets/machu_picchu_pano_original_4096x2048.jpg`
- Original 2048 preview: `docs/panos/assets/machu_picchu_pano_original_2048x1024.jpg`
- Original thumbnail: `docs/panos/assets/machu_picchu_pano_original_thumbnail.jpg`
- People-removed 4096 preview: `docs/panos/assets/machu_picchu_pano_people_removed_4096x2048.jpg`
- People-removed 2048 preview: `docs/panos/assets/machu_picchu_pano_people_removed_2048x1024.jpg`
- People-removed thumbnail: `docs/panos/assets/machu_picchu_pano_people_removed_thumbnail.jpg`

The un-gated package uses web-safe derivatives. Full-resolution copies are only written when `GHP_INCLUDE_FULLRES_PANO=1`.

## Related Reports

- [PANO_PEOPLE_CLEANUP_TEST.md](https://github.com/phdev/splat-tests/blob/main/spikes/mobile_vr_splat_feasibility/PANO_PEOPLE_CLEANUP_TEST.md)
- [SPAG4D_CLEANED_FULLRES_SHARP360_TEST.md](https://github.com/phdev/splat-tests/blob/main/spikes/mobile_vr_splat_feasibility/SPAG4D_CLEANED_FULLRES_SHARP360_TEST.md)

## Run

```bash
bash spikes/mobile_vr_splat_feasibility/scripts/package_panos_for_github_pages.sh
```

Optional overrides:

```bash
GHP_VIEWER_DIR=docs bash spikes/mobile_vr_splat_feasibility/scripts/package_panos_for_github_pages.sh
GHP_INCLUDE_FULLRES_PANO=1 bash spikes/mobile_vr_splat_feasibility/scripts/package_panos_for_github_pages.sh
```

## Deploy

Deployment is gated. Do not push unless `GH_PAGES_DEPLOY=1` is intentionally set.

```bash
GH_PAGES_DEPLOY=1 GHP_VIEWER_DIR=docs bash spikes/mobile_vr_splat_feasibility/scripts/deploy_viewer_assets.sh
```

If `docs/` is the detected Pages directory in the deployment environment, this equivalent form can be used:

```bash
GH_PAGES_DEPLOY=1 bash spikes/mobile_vr_splat_feasibility/scripts/deploy_viewer_assets.sh
```
