extends SceneTree
## Deterministic sizing of the supplied artwork. Never redraw the logo or its text.

func _initialize() -> void:
	var source := Image.load_from_file("res://assets/branding/pekaboo_logo_cutout.png")
	if source == null:
		quit(1)
		return
	source.convert(Image.FORMAT_RGBA8)
	var size := source.get_size()
	# Fit the full transparent silhouette, preserving faces, bow, and complete wordmark.
	var bounds := _visible_bounds(source).grow(12).intersection(Rect2i(Vector2i.ZERO, size))
	var logo := source.get_region(bounds)
	if logo.save_png("res://assets/branding/pekaboo_logo.png") != OK:
		quit(1)
		return
	var cream := Color("#fdf8e9")
	_save_fitted(logo, Vector2i(192, 192), Vector2i(174, 158), cream, "res://icon.png")
	_save_windows_icon(logo, cream)
	# Keep the complete artwork within the central area of Android's adaptive icon.
	_save_fitted(logo, Vector2i(432, 432), Vector2i(216, 200), Color.TRANSPARENT, "res://icon_432.png")
	var background := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	background.fill(cream)
	background.save_png("res://icon_bg_432.png")
	_save_fitted(logo, Vector2i(1280, 720), Vector2i(480, 440), cream, "res://desktop_splash.png")
	_save_fitted(logo, Vector2i(1280, 720), Vector2i(480, 440), cream, "res://splash.png")
	print("BRANDING source=%s cropped=%s; icons=192/432; splash=1280x720; background=%s" % [size, logo.get_size(), cream])
	print("BRANDING alpha=%s corner_alpha=%.4f" % [logo.detect_alpha(), source.get_pixel(0, 0).a])
	quit()

func _visible_bounds(image: Image) -> Rect2i:
	# Background extraction can leave imperceptible alpha specks in empty margins.
	# Only use visible pixels to measure the crop; never change artwork alpha or colors.
	var lo := image.get_size()
	var hi := Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.04:
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	return Rect2i(lo, hi - lo + Vector2i.ONE)

func _save_fitted(source: Image, canvas_size: Vector2i, bounds: Vector2i, background: Color, path: String) -> void:
	var scale := minf(float(bounds.x) / source.get_width(), float(bounds.y) / source.get_height())
	var fitted := source.duplicate() as Image
	fitted.resize(roundi(source.get_width() * scale), roundi(source.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(background)
	canvas.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), (canvas_size - fitted.get_size()) / 2)
	var error := canvas.save_png(path)
	if error != OK:
		push_error("Could not save branding asset " + path)
		quit(error)

func _save_windows_icon(logo: Image, cream: Color) -> void:
	var sizes := [16, 24, 32, 48, 64, 128, 256]
	var images: Array[PackedByteArray] = []
	for pixels: int in sizes:
		var fitted := logo.duplicate() as Image
		var width := roundi(pixels * 0.90)
		fitted.resize(width, roundi(float(width) * logo.get_height() / logo.get_width()), Image.INTERPOLATE_LANCZOS)
		var canvas := Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
		canvas.fill(cream)
		canvas.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), (Vector2i(pixels, pixels) - fitted.get_size()) / 2)
		images.append(canvas.save_png_to_buffer())
	var file := FileAccess.open("res://icon.ico", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_16(0)
	file.store_16(1)
	file.store_16(sizes.size())
	var offset := 6 + sizes.size() * 16
	for i in sizes.size():
		file.store_8(0 if sizes[i] == 256 else sizes[i])
		file.store_8(0 if sizes[i] == 256 else sizes[i])
		file.store_8(0)
		file.store_8(0)
		file.store_16(1)
		file.store_16(32)
		file.store_32(images[i].size())
		file.store_32(offset)
		offset += images[i].size()
	for data in images:
		file.store_buffer(data)
