source 'https://rubygems.org'
ruby '3.4.9'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

gem 'rails', '~> 8.0'
gem 'pg', '~> 1.5'
gem 'pg_search'
gem 'puma', '~> 6.0'
gem 'sprockets-rails'
gem 'sassc-rails'
gem 'turbolinks', '~> 5'
gem 'jbuilder', '~> 2.5'
gem 'roo'
gem 'kaminari'

group :development, :test do
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'capybara', '~> 3.39'
  gem 'selenium-webdriver'
end

group :development do
  gem 'web-console'
  gem 'listen'
end

group :test do
  gem 'cucumber-rails', require: false
  gem 'cucumber'
  gem 'rspec-rails'
  gem 'database_cleaner'
  gem 'factory_bot_rails'
  gem 'launchy'
end

gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
