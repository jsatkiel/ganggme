Menu art for the pause menu / loadout (scripts/pause_menu.gd). Every image is optional: the menu shows a
placeholder until a file with the right name is here. PNG, transparent background where it makes sense.

menu/background.png          full-screen art behind the pause menu (shown faded over the blurred game), 1920x1080

weapons/glock.png            weapon card / class art, side view, barrel pointing right, about 1000x400
weapons/ppq.png
weapons/compact.png
weapons/snub.png

attachments/comp.png         small square icons, 128x128
attachments/suppressor.png
attachments/extended.png
attachments/fastmag.png
attachments/laser.png
attachments/light.png
attachments/match.png
attachments/heavy.png

camos/factory.png            camo swatches, square, 256x256 (tiles you'd see on the gun)
camos/blackout.png
camos/tan.png
camos/od.png
camos/blue.png
camos/red.png
camos/chrome.png
camos/gold.png

perks/lightweight.png        perk icons, square, 128x128
perks/quickfix.png
perks/sleight.png
perks/steady.png
perks/stopping.png
perks/marathon.png

New guns, attachments, camos or perks: add them to scripts/loadout.gd and drop art here under the same id.
3D models for the other pistols (FBX/GLB) go in assets/props/<gun>/; until then they use the Glock model.
