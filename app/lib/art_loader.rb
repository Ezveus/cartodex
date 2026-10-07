require "vips"

# Decodes a card art fetched from a URL, with the loader named from the URL's extension — never
# sniffed from the bytes. Og::Renderer and Decks::ProxySheetExporter both draw remote arts, and both
# read them through here so that the rule cannot drift between a link preview and a proxy sheet.
#
# Why never sniff: `Vips::Image.new_from_buffer(bytes, "")` lets libvips choose by inspecting the
# bytes, so once Og::Renderer.allow_generated_svg! has unblocked the SVG loader the *CDN* decides
# which loader runs on its response — and librsvg is exactly the one upstream has not fuzzed.
# Measured through that path: a 16000x16000 SVG took 66.8 s and 1160 MB, and 25000x25000 never
# finished, wedging one of five Puma threads on a single unauthenticated request.
#
# Card arts are PNG or JPEG (Limitless serves `…_LG.png`). Anything else raises Vips::Error, which
# each caller turns into "this card has no art" in its own way.
module ArtLoader
  def self.load(bytes, url)
    case File.extname(URI.parse(url).path).downcase
    when ".jpg", ".jpeg" then Vips::Image.jpegload_buffer(bytes)
    when ".png"          then Vips::Image.pngload_buffer(bytes)
    else raise Vips::Error, "refusing to guess an image loader for #{url}"
    end
  end
end
