require "active_support/all"
require "nokogiri"
require "open-uri"

module Helpers
  extend ActiveSupport::NumberHelper
end

module Jekyll
  class GoogleScholarCitationsTag < Liquid::Tag
    Citations = {}

    def initialize(tag_name, params, tokens)
      super
      @scholar_id, @article_id = params.split.map(&:strip)
    end

    def render(context)
      scholar_id = @scholar_id && context[@scholar_id].to_s.strip
      article_id = @article_id && context[@article_id].to_s.strip
      return "N/A" if scholar_id.to_s.empty? || article_id.to_s.empty?

      key = [scholar_id, article_id]
      return Citations[key] if Citations.key?(key)

      query = URI.encode_www_form(
        view_op: "view_citation", hl: "en", user: scholar_id,
        citation_for_view: "#{scholar_id}:#{article_id}"
      )
      url = "https://scholar.google.com/citations?#{query}"
      value = "N/A"
      begin
        doc = URI.open(url, "User-Agent" => "Mozilla/5.0", open_timeout: 10, read_timeout: 10) do |response|
          Nokogiri::HTML(response)
        end

        # Prefer Scholar's visible citation link; descriptions may omit the count.
        texts = doc.css('a[href*="scholar?"]').map(&:text)
        texts.concat(doc.css('meta[name="description"], meta[property="og:description"]').map { |meta| meta["content"].to_s })
        match = texts.lazy.map { |text| text.match(/Cited by\s+([\d,]+)/i) }.find { |result| result }
        if match
          count = match[1].delete(",").to_i
          value = count < 1000 ? count.to_s : Helpers.number_to_human(count, format: "%n%u", precision: 2, units: { thousand: "K", million: "M", billion: "B" })
        end
        # Missing counts can indicate a blocked page, so never assume zero.
      rescue StandardError => e
        puts "Error fetching Google Scholar citations for #{article_id}: #{e.class} - #{e.message}"
      end

      Citations[key] = value
    end
  end
end

Liquid::Template.register_tag("google_scholar_citations", Jekyll::GoogleScholarCitationsTag)
