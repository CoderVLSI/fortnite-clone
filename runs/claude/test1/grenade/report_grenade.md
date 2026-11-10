# grenade

- Preview: `runs/claude/test1/grenade/preview_grenade.png`
- Triangles: 1,904 (budget 2,500)
- Size: 0.074 x 0.085 x 0.102 m (target about 0.11 m tall, 0.08 m body)
- Objects: `grenade_body`, `grenade_fuse`, `grenade_lever` (pivot at the cap), `grenade_ring` (pivot at the lug)
- Materials: `mat_olive`, `mat_olive_dark`, `mat_gunmetal`, `mat_gunmetal_dark`; colour and gradient are in the `Col` vertex colours, no image textures
- Self-correction loops: 2 (plate size and pole spikes, lever thickness and stand-off; then ring angle and a flat base)

Weakest: the plates are flat facets with a single chamfer step, so they look harder-edged than the soft pillowy plates on the reference.
