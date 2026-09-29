# Shaderpack Advanced

Advanced is a built-in ray-tracing shader pack for [Radiance](https://github.com/Minecraft-Radiance/Radiance), built on the ideas of [Vanilla PT](https://github.com/Minecraft-Radiance/Shaderpack-Vanilla-PT) with additional lighting, atmosphere, and material features. This source version corresponds to **Radiance 0.1.6-alpha**.

## Features

- ReSTIR direct-light sampling and a SHARC lighting cache.
- Indirect lighting, reflections, and transmission through transparent materials.
- Water waves, refraction, underwater rendering, and rain-driven surface wetness.
- Day and night atmosphere, volumetric lighting, clouds, fog, and exposure controls.
- PBR material support and optional parallax mapping.
- Quality presets and temporal data for Radiance's reconstruction pipelines.

Features and their cost depend on the selected settings. A PBR resource pack, such as [SPBR](https://modrinth.com/resourcepack/spbr), provides the material channels used by the corresponding effects.

## Using the pack

Advanced is included with Radiance 0.1.6-alpha and can be selected in its shader pack interface. A separate download is only needed when using a modified copy.

This is a Radiance shader pack. It uses the MCVR shader interface and is not an Iris or OptiFine shader pack. Use it with the matching Radiance / MCVR release.

To package a modified copy, put `configs.json` and the runtime directories at the root of a ZIP file. For example, from this repository:

```sh
zip -r Advanced-0.1.6.zip configs.json common core environment extern lang lighting output path scene textures util volume LICENSE
```

Place that ZIP in the game instance's `shaderpacks` directory, then choose it through Radiance's shader pack interface. Avoid an extra enclosing repository directory inside the ZIP.

## Source layout

| Directory | Content |
| --- | --- |
| `core`, `common`, `util` | Shader bindings, shared data structures, and common functions |
| `scene` | Geometry, materials, water, parallax, and hit evaluation |
| `path` | Primary, direct, indirect, and transmission paths |
| `lighting` | BSDFs, emitters, ReSTIR, shadows, and SHARC cache passes |
| `environment`, `volume` | Sky, atmosphere, clouds, and volumetric lighting |
| `output` | Radiance composition and post-render passes |
| `textures`, `lang` | Runtime assets and setting translations |
| `extern/sharc/include` | SHARC headers prepared for this release |

`configs.json` defines the resources, passes, and settings. The runtime files match the complete `advanced.zip` bundled with Radiance 0.1.6-alpha, including the shared files and prepared SHARC headers. Changes to shared structures must stay compatible with [MCVR](https://github.com/Minecraft-Radiance/MCVR).

Earlier comparison images remain in `figures/` as a record of previous versions.

## License

See [LICENSE](LICENSE). SHARC and other third-party source files retain their own notices and licenses.
