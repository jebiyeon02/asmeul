# Hollow soundscape sources

## Bundled field recordings

All three source pages were checked on 2026-09-13 and identify the audio as **CC0 1.0**. The prototype bundles the publicly served high-quality MP3 preview, not the downloadable original lossless WAV. Conversion to float PCM cannot restore compression losses. `Sources/Hollow/Resources/sources.json` records the exact download URLs.

| File | Work / creator | Source | Processing |
|---|---|---|---|
| cave.mp3 | cave dripping water / mentos987 | https://freesound.org/people/mentos987/sounds/818888/ | Stereo field recording; level matching, distance filtering, crossfaded loop |
| cave-echo.mp3 | Water Dripping in Cave.wav / Sclolex | https://freesound.org/people/Sclolex/sounds/177958/ | Artist's processed dripping recording; mixed below the dry cave layer |
| rain.mp3 | Rain (Heavy)_From open window.wav / KaleidacousticsAudio | https://freesound.org/people/KaleidacousticsAudio/sounds/630424/ | Stereo open-window recording; level matching, crossfaded loop |

License: https://creativecommons.org/publicdomain/zero/1.0/

## Original music and fictional radio

- `radio-jazz.wav`: an obsolete original 32-bar, 68 BPM jazz-style instrumental from the prototype. It is not part of the current release, and no sampled commercial songs or broadcast audio are used.
- DJ scripts: four original Japanese passages in `RadioVoiceBuilder.scripts`. A fictional station named Hollow Midnight Radio. No real news, live weather, cloned speakers or commercial radio program.
- DJ audio: rendered locally into memory using an available Japanese macOS system voice. Prefer enhanced/premium voices if already installed, otherwise Kyoko. No personal voice permission, network download, or user audio recording is used by Hollow. Voice quality depends on the installed voice; this is synthesized narration, not a human-recorded ASMR performance.
- `previews/*.wav`: offline examples rendered from Hollow's generated/owned or CC0 scene layers only. They do not contain captured system audio. These previews are not packaged into the application.

For a release-quality edition, audition lossless masters, replace the prototype narration with a commissioned Japanese DJ performance, and review voice/music distribution rights for the chosen release assets. No claim is made that the current synthesis sounds indistinguishable from a human performance.

## 0.3 update — reference-inspired office and lakeside

The former `radio-jazz.wav` is **not loaded, played, or bundled** in the current release. The radio and office signal paths never read a music bank. Historical 0.2 descriptions above refer to the previous version; obsolete source assets have been removed from the working tree.

Additional CC0 pages were checked directly on 2026-09-13; exact HQ preview URLs are recorded in `Resources/scene-sources.json`:

| File | Creator / original recording | Source |
|---|---|---|
| crickets.mp3 | adneonlux / Evening_crickets.wav; includes distant road | https://freesound.org/s/195707/ |
| lake.mp3 | TheFlyFishingFilmmaker / Gentle waves on a lake | https://freesound.org/s/614299/ |
| writing.mp3 | parkersenk / Writing with Pencil on Paper | https://freesound.org/s/444479/ |
| keyboard.mp3 | SamsterBirdies / Typing on a keyboard | https://freesound.org/s/489424/ |
| grass.mp3 | ciccarelli / GRASS IN THE WIND.wav; California, with distant freeway | https://freesound.org/s/135870/ |
| city.mp3 | TRP / quiet distant residential traffic recorded in Toronto | https://freesound.org/s/572530/ |

Tokyo Office is a fictional atmosphere assembled from these recordings, not a claim that the stock layers were recorded in Tokyo.

`twilight-piano.wav` and `memory-chimes.wav` are original synthesis created for this version by `scripts/make_twilight.py`, with sparse piano voicings, distant bell/wood impulses and reflections. They do not copy the reference videos' compositions. Both are 96-second scenes. The piano bank is used only by Twilight Lake.

The four 0.3 Japanese scripts are fictional neighborhood/cultural broadcast passages, clearly labeled as generated fictional broadcasts in the app. No actual current events, named real broadcaster, source video speech, or commercial broadcast audio is used.
