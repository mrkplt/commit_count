require 'net/http'
require 'json'
require 'open3'

class Gateway
  attr_reader :url

  def initialize(login, pass, url)
    @login = login
    @pass = pass
    @url = url
  end

  def parsed_response(uri)
    JSON.parse(call(uri).body)
  end

  private

  def call(uri)
    Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(login, pass)
      http.request(request)
    end
  end

  attr_reader :login, :pass
end

class RepositoryCollection
  def initialize(project_key, gateway)
    @project_key = project_key
    @gateway = gateway
  end

  def all
    @repos ||= repos.map do |repo|
      Repository.new(repo)
    end
  end

  private

  attr_reader :project_key, :gateway

  def uri
    URI("#{gateway.url}/projects/#{project_key}/repos")
  end

  def repos
    @repos ||= gateway.parsed_response(uri)['values']
  end
end

class ProjectCollection
  def initialize(gateway)
    @gateway = gateway
  end

  def all
    @all ||= projects.map do |body|
      Project.new(body)
    end
  end

  private

  attr_reader :gateway

  def uri
    URI("#{gateway.url}/projects")
  end

  def projects
    @projects ||= gateway.parsed_response(uri)['values']
  end
end

class Repository
  def initialize(body)
    @body = body
  end

  def slug
    body['slug']
  end

  def url
    body['links']['clone'].detect{|link| link['name'] == 'ssh'}['href']
  end

  def clone
    Open3.capture3("git clone #{url}")
  end

  def directory
    Dir.pwd + '/' + slug
  end

  def run_in_directory
    Dir.chdir(directory) { yield if block_given? }
  end

  def count
    run_in_directory do
      Open3.capture3(
        "git whatchanged --since='one year ago' --pretty=oneline | wc -l"
      )[0].to_i
    end
  end

  def destroy_local
    Open3.capture3("rm -rf #{slug}")
  end

  private

  attr_reader :body
end

class Project
  def initialize(body)
    @body = body
  end

  def key
    body['key']
  end

  private

  attr_reader :body
end

# irb -I . -r curl2.rb
#
# gateway = Gateway.new('user)name', 'password', 'https://your.stash.url.com/rest/api/1.0')
#
# repos = ProjectCollection.new(gateway).all.map(&:key).flat_map do |key|
#   RepositoryCollection.new(key, gateway).all
# end
#
# count = repos.map do |repo|
#   repo.clone
#   repo.count
# end.reduce(:+)
#
# repos.each(&:destroy_local)
#
# count
