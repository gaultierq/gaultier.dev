require 'middleman-core/renderers/redcarpet'
# or require 'redcarpet' if you want to subclass directly

class MyCustomRenderer < Middleman::Renderers::MiddlemanRedcarpetHTML
  NOTE_CALLOUT = /^\[!note:(?<id>[\w-]+)\]\n(?<content>(?:.*?\n)*?)^\[\/!note:(?<id2>[\w-]+)\]$/m.freeze

  def initialize(options={})
    @local_options = options.dup

    super
  end

  def preprocess(document)
    # Instantiate another renderer inside this renderer.
    markdown = Redcarpet::Markdown.new(self, fenced_code_blocks: true)

    # Change every instance of the CALLOUT regex in place.
    document.gsub!(NOTE_CALLOUT) do |match|
      # Use CALLOUT again to grab the named captures.
      m = NOTE_CALLOUT.match(match).named_captures

      # Remove the leading "" from each line of the content.
      content = m['content']

      # Render out the component, with nested markdown rendering.
      "<div class='hidden' id='#{m['id']}'>#{markdown.render(content)}</div>"
    end


    document
  end
end
