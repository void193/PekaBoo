class_name Custom
## What a couple can make their own without touching the game files:
##   Pictures/PekaBoo/*.jpg|png|webp   -> hang in the picture frames around the house
##   Movies/PekaBoo/*.ogv              -> play on the living room TV (otherwise the TV slideshows the photos)
## On a phone these are the normal "Pictures" and "Movies" folders; on a computer the same folders in your home.

const IMAGES := ["jpg", "jpeg", "png", "webp"]
const VIDEOS := ["ogv"]
const MAX_SIDE := 1280


static func photo_dir() -> String:
	var p := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	return (p if p != "" else OS.get_user_data_dir()) + "/PekaBoo"


static func tv_dir() -> String:
	var p := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
	return (p if p != "" else OS.get_user_data_dir()) + "/PekaBoo"


static func _list(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() in exts and not f.begins_with("."):
			out.append(dir + "/" + f)
	out.sort()
	return out


static func photos() -> Array[String]:
	return _list(photo_dir(), IMAGES)


static func videos() -> Array[String]:
	return _list(tv_dir(), VIDEOS)


static func load_photo(path: String) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	var m := maxi(img.get_width(), img.get_height())
	if m > MAX_SIDE:
		var s := float(MAX_SIDE) / float(m)
		img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
