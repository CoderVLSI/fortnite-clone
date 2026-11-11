# Character models and animations

`Soldier.glb`, `Xbot.glb` and `Michelle.glb` are Mixamo characters and animations (Adobe Mixamo),
taken from the three.js examples (`examples/models/gltf/` in https://github.com/mrdoob/three.js).

- Soldier: the playable body, with its Idle, Walk and Run clips.
- Xbot: extra clips (idle, walk, run, sneak, agree, head shake) used on the Soldier.
- Michelle: the samba dance, for the emote.

All three are retargeted at import onto Godot's humanoid skeleton (`mixamo_bonemap.tres`, set in
each `.glb.import`), which is what lets one character play the others' clips.

Adobe allows Mixamo characters and animations to be used inside games and other projects, but not
to be redistributed as stand-alone files. These copies were not downloaded under this project's
own Adobe account. Before publishing the game, replace them with files downloaded from mixamo.com
under your own account (same names and the same import settings will work).
