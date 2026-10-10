# Hand-held map assets

Built by art/scripts/fp_map.py (Blender scene MapWork, saved to art/map.blend).

- parchment_front.png, parchment_back.png, parchment_n.png: baked in Blender from procedural nodes
  over ambientCG Paper001 (fibre height), Paper002 (fibre flecks) and Paper003 (crumple colour and
  height) (https://ambientcg.com/a/Paper001 etc.), all CC0 1.0.
- map.glb: the folded sheet, its fold rig and the "unfold" animation, modelled from scratch.
- map_hand.glb: a mirrored, re-posed copy of the first-person glove (CC0 Blender Studio Human Base
  Meshes hand, see client/assets/ring1/), with textures baked by art/scripts/bake_export.py.
- The map's lettering uses the IM Fell fonts in client/assets/fonts/ (SIL Open Font License, see
  OFL-IM-Fell.txt there).
