# Icons

The inventory and HUD icons in this folder were generated with an image model
(`google/gemini-3.1-flash-lite-image` through OpenRouter) by `tools/gen_icons.py`. Each item icon
was drawn from a render of the game's own 3D asset, so it matches the model in the game. The model
painted on a magenta background, which the script keys out to transparency. The untouched outputs
are in `raw/`.

The original challenge in the video did not allow AI image generation. That rule was about the 3D
assets; these 2D icons were added later at the project owner's request.
