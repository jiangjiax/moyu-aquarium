"""生成全部像素素材到 godot/art/。

    python3 tools/make_art.py            # 出图
    python3 tools/make_art.py --preview  # 另出一张放大的验收图到 godot/shots/
    python3 tools/make_art.py --fine     # 出精细版（默认是粗糙版，见 px_core.ROUGH）

改完要让 Godot 重新导入：cd godot && godot --headless --import
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import decor  # noqa: E402
import fish  # noqa: E402
import px_core  # noqa: E402
from px_core import pad, preview  # noqa: E402

SWAY_PAD = 3

OUT = os.path.join(HERE, "..", "godot", "art")

# 装饰清单：名字 -> (生成函数, 参数)。场景里按名字取
DECOR = {
    "rock_xl": (decor.rock, (46, 22, 8, "#858c96")),
    "rock_l": (decor.rock, (34, 16, 1)),
    "rock_m": (decor.rock, (22, 11, 2, "#7f8894")),
    "rock_s": (decor.rock, (12, 6, 3, "#949aa2", False)),
    "rock_xs": (decor.rock, (7, 4, 4, "#a0a4aa", False)),
    "coral_big": (decor.branch_coral, (32, 40, 21)),
    "coral_pink": (decor.branch_coral, (22, 30, 4)),
    "coral_coral": (decor.branch_coral, (18, 24, 9, "#ee9a78")),
    "brain": (decor.brain_coral, (20, 11, 2)),
    "brain_l": (decor.brain_coral, (28, 15, 5, "#a3b85a")),
    "fan": (decor.sea_fan, (24, 30, 6)),
    "fan_s": (decor.sea_fan, (16, 20, 12, "#8f7cc8")),
    "anemone": (decor.anemone, (18, 14, 1)),
    "kelp_a": (decor.kelp, (11, 58, 1)),
    "kelp_b": (decor.kelp, (11, 44, 5, "#6cb87a")),
    "grass_a": (decor.grass, (12, 12, 1)),
    "grass_b": (decor.grass, (9, 9, 3, "#8ccb72")),
    "starfish": (decor.starfish, ()),
    "shell": (decor.shell, ()),
}


def main():
    px_core.ROUGH = "--fine" not in sys.argv
    out = os.environ.get("ART_OUT", OUT)     # 自检时可以出到别的目录比对
    os.makedirs(out, exist_ok=True)
    meta = {"fish": {}, "decor": {}}
    fish_imgs = []
    for name, fn in fish.ALL.items():
        img = fn()
        img.save(os.path.join(out, f"fish_{name}.png"))
        meta["fish"][name] = {"frames": len(fish.FRAMES), "w": img.width // len(fish.FRAMES),
                              "h": img.height}
        fish_imgs.append(img.crop((0, 0, img.width // len(fish.FRAMES), img.height)))
    decor_imgs = []
    for name, (fn, args) in DECOR.items():
        img = fn(*args)
        decor_imgs.append(img)
        sway = name.startswith(("kelp", "grass", "fan", "anemone"))
        if sway:
            # 摇摆 shader 会把上半截横移，左右留空边，不然会被贴图边界切掉
            img = pad(img, SWAY_PAD, 0, SWAY_PAD, 0)
        img.save(os.path.join(out, f"deco_{name}.png"))
        meta["decor"][name] = {"w": img.width, "h": img.height, "sway": sway,
                               "pad": SWAY_PAD if sway else 0}
    decor.sand_tile().save(os.path.join(out, "sand.png"))
    decor.backdrop_tile().save(os.path.join(out, "backdrop.png"))
    decor.dust().save(os.path.join(out, "dust.png"))
    decor.frame_ninepatch().save(os.path.join(out, "frame.png"))
    decor.icon("expand").save(os.path.join(out, "icon_expand.png"))
    decor.icon("collapse").save(os.path.join(out, "icon_collapse.png"))
    for r in (1, 2, 3):
        decor.bubble(r).save(os.path.join(out, f"bubble_{r}.png"))
    with open(os.path.join(out, "meta.json"), "w") as f:
        json.dump(meta, f, indent=1)

    if "--preview" in sys.argv:
        shots = os.path.join(HERE, "..", "godot", "shots")
        os.makedirs(shots, exist_ok=True)
        preview(decor_imgs[:9], os.path.join(shots, "decor_preview_a.png"), scale=6)
        preview(decor_imgs[9:] + [decor.frame_ninepatch()],
                os.path.join(shots, "decor_preview_b.png"), scale=6)
        preview([decor.sand_tile(), decor.backdrop_tile()],
                os.path.join(shots, "env_preview.png"), scale=4)
    print("ok", len(meta["fish"]), "fish,", len(meta["decor"]), "decor")


if __name__ == "__main__":
    main()
