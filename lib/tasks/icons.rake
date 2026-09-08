namespace :icons do
  desc "Rasterise the icon SVGs into the committed PNGs, so the derived files cannot drift unnoticed"
  task build: :environment do
    # The SVGs are the source of truth and the PNGs are committed derivatives, which is a pair that
    # rots quietly: edit icon.svg, forget the raster, and the favicon a browser actually shows is
    # the old drawing while the repo looks correct. This task is what makes that visible — re-run
    # it and `git status` names every PNG that had drifted. Nothing runs it at boot; the production
    # image serves the committed files.
    #
    # `:environment`, and the first version's reasoning for avoiding it was wrong twice over.
    # Skipping it does not skip ActiveStorage — Vips.block_untrusted(true) runs at *require* time
    # of active_storage/vips.rb, which `require "rails/all"` in config/application pulls in, and
    # the Rakefile requires config/application before it defines a single task, so svgload is
    # blocked here exactly as it is in a request. Measured: the task raised Vips::Error on its
    # first image, so the anti-drift mechanism it *is* produced nothing at all. And the unblock
    # below reads an autoloaded constant, which needs the initializers Zeitwerk is set up by.
    require "vips"

    # Two drawings, not one. `icon.svg` carries the bench, `icon-small.svg` does not: rendered at
    # 84px the five slots collapse into indistinguishable grey pips, so below roughly 48px they are
    # noise, and the 16 and 32 pixel favicons come from the reduced mark. `icon-maskable.svg` is
    # the third, for Android's circular crop: it is the only one with an opaque ground, which is
    # why a maskable manifest entry cannot simply point at the full-bleed drawing.
    specs = [
      { source: "icon.svg",          size: 512, output: "icon-512.png" },
      { source: "icon.svg",          size: 192, output: "icon-192.png" },
      { source: "icon-maskable.svg", size: 512, output: "icon-maskable-512.png" },
      { source: "icon-small.svg",    size: 32,  output: "icon-32.png" },
      { source: "icon-small.svg",    size: 16,  output: "icon-16.png" }
    ]

    public_dir = Rails.root.join("public")

    Og::Renderer.allow_generated_svg!

    specs.each do |spec|
      source = public_dir.join(spec[:source])
      output = public_dir.join(spec[:output])
      size = spec[:size]

      # thumbnail rather than a load-then-resize: libvips passes the target size down into
      # svgload, so the vector is rendered at the final resolution instead of being rasterised
      # once and then resampled — which is what keeps the 16px favicon's edges from smearing.
      Vips::Image.thumbnail(source.to_s, size, height: size).write_to_file(output.to_s)

      puts "#{spec[:output]}: #{size}x#{size}, from #{spec[:source]}"
    end

    # The layout and the manifest have referenced /icon.png since `rails new` wrote it, and so may
    # things this repo cannot see — a bookmark, an aggregator that already cached the path. Keeping
    # it a copy of the 512 raster means the generator's filename stays correct rather than stale.
    icon_png = public_dir.join("icon.png")
    icon_png.binwrite(public_dir.join("icon-512.png").binread)
    puts "icon.png: copy of icon-512.png"
  end
end

namespace :og do
  desc "Render public/og-default.jpg, the static Cartodex banner every page without artwork uses"
  task default_banner: :environment do
    # The other committed derivative, and it is here for that reason: generated art a reviewer has
    # to be able to regenerate. Every page outside the three surfaces that have artwork to show
    # gets this banner, so it must exist as a file — no request path builds it.
    path = Rails.root.join("public/og-default.jpg")
    path.binwrite(Og::Renderer.call(Og::SitePayload.call).bytes)

    puts "Wrote #{path.relative_path_from(Rails.root)} (#{path.size} bytes)."
  end
end
