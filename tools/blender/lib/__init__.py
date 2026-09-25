## tools/blender/lib/__init__.py
## Fait de "lib" un vrai package Python, pour que
## `sys.path.insert(0, os.path.dirname(__file__)); import toonkit`
## (depuis un script lancé par `blender -b -P tools/blender/xxx.py`) fonctionne
## sans installation ni PYTHONPATH particulier. Ne rien mettre d'autre ici :
## tout le contenu réutilisable vit dans toonkit.py (voir docs/3D_PIPELINE.md).
