# Activate and configure extensions
# https://middlemanapp.com/advanced/configuration/#configuring-extensions

require 'slim'

set :site_url, 'https://gaultier.dev'
set :site_title, 'Personal Blog' # site title for <title> meta tag
set :site_description, 'Personal Blog' # site title for <title> meta tag
set :trailing_slash, false

activate :autoprefixer do |prefix|
  prefix.browsers = 'last 2 versions'
end

# Layouts
# https://middlemanapp.com/basics/layouts/

# Per-page layout changes
page '/*.xml', layout: false
page '/*.json', layout: false
page '/*.txt', layout: false

activate :external_pipeline,
         name: :tailwind,
         command: "yarn tailwindcss -i ./source/stylesheets/site.css -o ./dist/stylesheets/site.css #{unless build?
                                                                                                        '--watch'
                                                                                                      end}",
         latency: 2,
         source: './dist/'

activate :external_pipeline,
         name: :tailwind,
         command: "yarn tailwindcss -i ./source/stylesheets/resume.css -o ./dist/stylesheets/resume.css #{unless build?
                                                                                                            '--watch'
                                                                                                          end}",
         latency: 2,
         source: './dist/'

# https://github.com/edgecase/middleman-gh-pages?tab=readme-ov-file#project-page-path-issues
activate :relative_assets
set :relative_links, true

activate :importmap do |options|
  options.entrypoint = 'site'
  options.importmap = 'importmap.json'
  options.use_shim = false
end

# set :markdown_engine, :redcarpet
# set :markdown,
#     fenced_code_blocks: true,
#     smartypants: true,
#     with_toc_data: true  # <-- This adds id attributes to headings

require_relative 'lib/my_custom_renderer'
set :markdown_engine, :redcarpet
set :markdown,
    renderer: MyCustomRenderer.new(
      with_toc_data: true,
      hard_wrap: false,
      prettify: true,
      xhtml: true
    ),
    fenced_code_blocks: true,
    autolink: true,
    smartypants: true,
    no_intra_emphasis: true

# With alternative layout
# page '/path/to/file.html', layout: 'other_layout'

# Proxy pages
# https://middlemanapp.com/advanced/dynamic-pages/
# proxy "/this-page-has-no-template.html", "/template-file.html", locals: {
#  which_fake_page: "Rendering a fake page with a local variable" }

# Activate and configure blog extension

activate :blog do |blog|
  # This will add a prefix to all links, template references and source paths
  # blog.prefix = "blog"

  # blog.permalink = "{year}/{month}/{day}/{title}.html"
  # Matcher for blog source files
  # blog.sources = "{year}-{month}-{day}-{title}.html"
  # blog.taglink = "tags/{tag}.html"
  blog.layout = 'article_layout'
  # blog.summary_separator = /(READMORE)/
  # blog.summary_length = 250
  # blog.year_link = "{year}.html"
  # blog.month_link = "{year}/{month}.html"
  # blog.day_link = "{year}/{month}/{day}.html"
  # blog.default_extension = ".markdown"

  blog.tag_template = 'tag.html'
  blog.calendar_template = 'calendar.html'

  # Enable pagination
  # blog.paginate = true
  # blog.per_page = 10
  # blog.page_link = "page/{num}"
end

page '/feed.xml', layout: false
# Reload the browser automatically whenever files change
configure :development do
  activate :livereload
end

# Helpers
# Methods defined in the helpers block are available in templates
# https://middlemanapp.com/basics/helper-methods/

helpers do
  def tag_list(tags)
    content_tag :div, class: 'badges' do
      tags.split(',').map(&:strip).map do |tag|
        content_tag(:span, tag)
      end.join("\n")
    end
  end

  def cute_link_to(link, &block)
    content_tag :a, class: 'relative group', href: link, target: 'blank' do
      a = "<span class='bg-accent opacity-20 rounded absolute z-0 scale-x-[0] group-hover:scale-x-[1] transition-transform ease-global motion-safe:duration-300 motion-reduce:duration-0 origin-left' style='top: -0.1rem; left: -0.3rem; width: calc(100% + 0.6rem); height: calc(100% + 0.2rem);' ></span>"
      b = content_tag(:span, class: 'relative z-10 underline sm:no-underline decoration-gray-200', &block)
      a + b
    end
  end
end

Slim::Engine.set_options shortcut: { '@' => { tag: 'span', additional_attrs: { class: 'tag' } },
                                     '.' => { attr: 'class' } }

# Build-specific configuration
# https://middlemanapp.com/advanced/configuration/#environment-specific-settings

page '/resume', layout: 'resume'
