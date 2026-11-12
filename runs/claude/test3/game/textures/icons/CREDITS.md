# Icons

The inventory and HUD icons in this folder were generated with an image model
(`google/gemini-3.1-flash-lite-image` through OpenRouter) by `tools/gen_icons.py`. Each item icon
was drawn from a render of the game's own 3D asset, so it matches the model in the game. The model
painted on a magenta background, which the script keys out to transparency. The untouched outputs
are kept in `raw/` locally and not committed. 31 icons cost 1.04 USD in total. Seven more (smg, tactical_shotgun, burst_rifle, hunting_rifle, bandages, hydro_juice, mega_flask) were added later the same way, from renders of the in-game models kept in `tools/refs/`, for 0.24 USD; the four gun icons were then redone from the Blender renders of the new guns (`runs/claude/test3/assets_src/`) for 0.14 USD (1.42 USD in all).

The original challenge in the video did not allow AI image generation. That rule was about the 3D
assets; these 2D icons were added later at the project owner's request.
