# dmgbuild settings for Kliq.dmg, used by Tools/make_dmg.sh. dmgbuild writes the
# Finder layout straight into the image, so building it never scripts Finder.
# Icon positions are icon centers in window points and must match Tools/dmg.html.
import os.path

app = defines["app"]
app_name = os.path.basename(app)

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]
icon = "Resources/AppIcon.icns"
background = "Resources/DMGBackground.tiff"
format = "UDZO"

window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {app_name: (180, 250), "Applications": (480, 250)}
