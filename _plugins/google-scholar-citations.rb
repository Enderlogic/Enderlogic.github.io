require "active_support/all"

module Helpers
  extend ActiveSupport::NumberHelper
end

module Jekyll
  class GoogleScholarCitationsTag < Liquid::Tag
    def initialize(tag_name, params, tokens)
      super
      @scholar_id, @article_id = params.split.map(&:strip)
    end

    def render(context)
      scholar_id = @scholar_id && context[@scholar_id].to_s.strip
      article_id = @article_id && context[@article_id].to_s.strip
      return "N/A" if scholar_id.to_s.empty? || article_id.to_s.empty?

      data = context["site.data.google_scholar_citations"]
      return "N/A" unless data && data["scholar_id"] == scholar_id

      count = data.fetch("citations", {})[article_id]
      return "N/A" unless count.is_a?(Integer) && count >= 0
      return count.to_s if count < 1000

      Helpers.number_to_human(count, format: "%n%u", precision: 2,
                             units: { thousand: "K", million: "M", billion: "B" })
    end
  end
end

Liquid::Template.register_tag("google_scholar_citations", Jekyll::GoogleScholarCitationsTag)
