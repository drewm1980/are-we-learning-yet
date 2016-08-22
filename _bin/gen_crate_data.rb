#!/bin/env ruby

require 'fileutils'
require 'json'
require 'yaml'
require 'net/http'

GH_OAUTH_TOKEN = ENV['GITHUB_OAUTH_TOKEN']

def die(msg)
	puts msg
	exit 1
end

def cached_curl(url, headers={})
  dir = url.sub(/^https?:\/\//, '/tmp/')
	path = File.join(dir, "index.json")
	FileUtils.mkdir_p(dir)
	unless File.exists? path
		uri = URI(url)
    req = Net::HTTP::Get.new(uri)
		headers&.each { |k,v| req[k] = v }
		res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => (uri.scheme == 'https')) { |http|
			http.request(req)
		}
		if res.is_a?(Net::HTTPSuccess)
			data = res.body
			File.open(path, 'w') do |f|
				f.write data
			end
		else
		  puts "#{res.code}: #{res.message} for #{url}"
			return {}
		end
	end
	JSON.parse(File.read(path))
end

def get_repo_data(repo)
  headers = {'Authorization': "token #{GH_OAUTH_TOKEN}"} if GH_OAUTH_TOKEN
	data = cached_curl("https://api.github.com/repos/#{repo}", headers)
	unless data.empty?
		branch = data['default_branch'] || 'master'
		commit = cached_curl("https://api.github.com/repos/#{repo}/commits/#{branch}", headers)
		contributors = cached_curl("https://api.github.com/repos/#{repo}/contributors", headers)
	end

	out = {}
	%w(stargazers_count open_issues_count).each do |k|
		out[k] ||= data[k]
	end
	out['last_commit'] = commit&.dig('commit', 'committer', 'date')
	out['contributor_count'] = contributors&.length
	out.delete_if { |k,v| v.nil? }
end

def get_crate_data(crate)
	data = cached_curl("https://crates.io/api/v1/crates/#{crate}")

	out = {}
	%w(description repository documentation downloads license max_version created_at updated_at).each do |k|
		out[k] = data.dig('crate', k)
	end
	out.delete_if { |k,v| v.nil? }
end

def read_crate_list
   YAML.load_file(File.join(__dir__, "../_data/crates.yaml"))
end

def save_crate_list(crates)
	puts "Saving crate list..."
	File.open(File.join(__dir__, "../_data/crates_generated.yaml"), 'w') do |f|
		f.write crates.to_yaml
	end
end


crates = read_crate_list.map do |crate|
	die "ERROR: crate entry is invalid: #{crate}" unless crate['name'] || crate['repository']

	puts "Processing #{crate['name'] || crate['repository']}"

	# Get data from the Crates.io API
	if crate['name']
		crate_data = get_crate_data(crate['name'])
		crate = crate_data.merge(crate)
	else
	  puts "WARNING: No crates.io name specified for #{crate['repository']}"
	end


	# Get data from the GitHub API
	matches = crate['repository']&.match(/github.com\/([^\.\/]+\/[^\.\/]+)/)
	repo = matches[1] if matches
	if repo
		repo_data = get_repo_data(repo)
		crate = repo_data.merge(crate)
		crate['github'] = repo
	else
	  puts "WARNING: No GitHub repository specified for crate #{crate['name']}"
	end

	puts "WARNING: Docs missing for crate #{crate['name']}" unless crate['documentation']

	crate
end

save_crate_list(crates)