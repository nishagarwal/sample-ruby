require 'yaml'

  # again - it's a singleton, thus implemented as a self-extended module
  # extend self
class Settings
  attr_accessor :username, :password
  def initialize file
  	config = YAML.load_file file
    @username = config["username"]
    @password = config["password"]
  end
end
