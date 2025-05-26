site_url   = config.site_url
title      = config.site_title
desc       = config.site_description

# All posts in reverse‑chronological order
posts = blog.articles.sort_by(&:date).reverse

xml.instruct! :xml, version: '1.0', encoding: 'utf-8'
xml.rss version: "2.0",
        "xmlns:atom" => "http://www.w3.org/2005/Atom",
        "xmlns:content" => "http://purl.org/rss/1.0/modules/content/" do
 xml.channel do
  xml.title title
  xml.link site_url
  xml.description desc
  xml.language    'en-us'
  xml.lastBuildDate(posts.first.date.to_time.rfc2822) if posts.any?
  xml.tag!("atom:link", href: "#{site_url}/feed.xml", rel: "self", type: "application/rss+xml")

  posts.each do |post|
   xml.item do
    xml.guid        "#{site_url}#{post.url}"
    xml.link        "#{site_url}#{post.url}"
    xml.title post.data.title
    xml.pubDate post.date.to_time.rfc2822
    xml.description post.summary, type: 'html'
    xml.tag!("content:encoded") { xml.cdata!(post.body) }
   end
  end
 end
end
