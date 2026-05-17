#!/usr/bin/env ruby
#
# Check for changed posts

Jekyll::Hooks.register :posts, :post_init do |post|

  begin
    commit_num = `git rev-list --count HEAD "#{ post.path }"`

    if commit_num.to_i > 1
      lastmod_date = `git log -1 --pretty="%ad" --date=iso "#{ post.path }"`.strip
      post.data['last_modified_at'] = lastmod_date unless lastmod_date.empty?
    end
  rescue SystemCallError
    # Git metadata is optional; don't fail the whole site when unavailable.
  end

end
