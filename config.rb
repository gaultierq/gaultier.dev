# Activate and configure extensions
# https://middlemanapp.com/advanced/configuration/#configuring-extensions

require 'slim'

activate :autoprefixer do |prefix|
  prefix.browsers = "last 2 versions"
end

# Layouts
# https://middlemanapp.com/basics/layouts/

# Per-page layout changes
page '/*.xml', layout: false
page '/*.json', layout: false
page '/*.txt', layout: false


activate :external_pipeline,
         name: :tailwind,
         command: "yarn tailwindcss -i ./source/stylesheets/site.css -o ./dist/stylesheets/site.css #{"--watch" unless build?}",
         latency: 2,
         source: "./dist/"

# https://github.com/edgecase/middleman-gh-pages?tab=readme-ov-file#project-page-path-issues
activate :relative_assets
set :relative_links, true

# With alternative layout
# page '/path/to/file.html', layout: 'other_layout'

# Proxy pages
# https://middlemanapp.com/advanced/dynamic-pages/

# proxy(
#   '/this-page-has-no-template.html',
#   '/template-file.html',
#   locals: {
#     which_fake_page: 'Rendering a fake page with a local variable'
#   },
# )

# Helpers
# Methods defined in the helpers block are available in templates
# https://middlemanapp.com/basics/helper-methods/

helpers {
  def tag_list(tags)
    content_tag :div, class: 'badges' do
      tags.split(',').map(&:strip).map do |tag|
        content_tag(:span, tag)
      end.join("\n")
    end
  end

  def cute_link_to(link)
    content_tag :a, class: 'relative group', href: link, target: 'blank' do
      a = "<span class='bg-accent opacity-20 rounded absolute z-0 scale-x-[0] group-hover:scale-x-[1] transition-transform ease-global motion-safe:duration-300 motion-reduce:duration-0 origin-left' style='top: -0.1rem; left: -0.3rem; width: calc(100% + 0.6rem); height: calc(100% + 0.2rem);' ></span>"
      b = content_tag(:span, class: 'relative z-10 underline sm:no-underline decoration-gray-200') do
        yield
      end
      a + b
    end
  end

}

Slim::Engine.set_options shortcut: {'@' => {tag: 'span', additional_attrs: { class: "tag" }}, '.' => { attr: "class" } }



# Build-specific configuration
# https://middlemanapp.com/advanced/configuration/#environment-specific-settings

# configure :build do
#   activate :minify_css
#   activate :minify_javascript, compressor: Terser.new
# end
