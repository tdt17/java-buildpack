# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright 2013 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'java_buildpack/container'
require 'java_buildpack/container/container_utils'
require 'java_buildpack/repository/configured_item'
require 'java_buildpack/util/application_cache'
require 'java_buildpack/util/format_duration'
require 'java_buildpack/util/resource_utils'

module JavaBuildpack::Container

  # Encapsulates the detect, compile, and release functionality for Tomcat applications.
  class Tomcat

    # Creates an instance, passing in an arbitrary collection of options.
    #
    # @param [Hash] context the context that is provided to the instance
    # @option context [String] :app_dir the directory that the application exists in
    # @option context [String] :java_home the directory that acts as +JAVA_HOME+
    # @option context [Array<String>] :java_opts an array that Java options can be added to
    # @option context [String] :lib_directory the directory that additional libraries are placed in
    # @option context [Hash] :configuration the properties provided by the user
    def initialize(context)
      context.each { |key, value| instance_variable_set("@#{key}", value) }
      if Tomcat.web_inf? @app_dir
        @tomcat_version, @tomcat_uri = Tomcat.find_tomcat(@configuration)
        @support_version, @support_uri = Tomcat.find_support(@configuration)
      else
        @tomcat_version, @tomcat_uri = nil, nil
        @support_version, @support_uri = nil, nil
      end
    end

    # Detects whether this application is a Tomcat application.
    #
    # @return [String] returns +tomcat-<version>+ if and only if the application has a +WEB-INF+ directory, otherwise
    #                  returns +nil+
    def detect
      @tomcat_version ? [tomcat_id(@tomcat_version), tomcat_support_id(@support_version)] : nil
    end

    # Downloads and unpacks a Tomcat instance and support JAR
    #
    # @return [void]
    def compile
      download_tomcat
      download_support
      link_application
      link_libs
    end

    # Creates the command to run the Tomcat application.
    #
    # @return [String] the command to run the application.
    def release
      @java_opts << "-D#{KEY_HTTP_PORT}=$PORT"

      java_home_string = "JAVA_HOME=#{@java_home}"
      java_opts_string = ContainerUtils.space("JAVA_OPTS=\"#{ContainerUtils.to_java_opts_s(@java_opts)}\"")
      start_script_string = ContainerUtils.space(File.join TOMCAT_HOME, 'bin', 'catalina.sh')

      "#{java_home_string}#{java_opts_string}#{start_script_string} run"
    end

    private

    KEY_HTTP_PORT = 'http.port'.freeze

    KEY_SUPPORT = 'support'.freeze

    TOMCAT_HOME = '.tomcat'.freeze

    WEB_INF_DIRECTORY = 'WEB-INF'.freeze

    def download_tomcat
      JavaBuildpack::Util::ApplicationCache.download('Tomcat', @tomcat_version, @tomcat_uri) do |file|
        expand(file, @configuration)
      end
    end

    def download_support
      JavaBuildpack::Util::ApplicationCache.download_jar(@support_version, @support_uri, 'Buildpack Tomcat Support', support_jar_name(@support_version), File.join(tomcat_home, 'lib'))
    end

    def expand(file, configuration)
      expand_start_time = Time.now
      print "       Expanding Tomcat to #{TOMCAT_HOME} "

      system "rm -rf #{tomcat_home}"
      system "mkdir -p #{tomcat_home}"
      system "tar xzf #{file.path} -C #{tomcat_home} --strip 1 --exclude webapps --exclude #{File.join 'conf', 'server.xml'} --exclude #{File.join 'conf', 'context.xml'} 2>&1"

      JavaBuildpack::Util::ResourceUtils.copy_resources('tomcat', tomcat_home)
      puts "(#{(Time.now - expand_start_time).duration})"
    end

    def self.find_tomcat(configuration)
      JavaBuildpack::Repository::ConfiguredItem.find_and_wrap_exceptions('Tomcat container', configuration) do |candidate_version|
        candidate_version.check_size(3)
      end
    end

    def self.find_support(configuration)
      JavaBuildpack::Repository::ConfiguredItem.find_item(configuration[KEY_SUPPORT])
    end

    def tomcat_id(version)
      "tomcat-#{version}"
    end

    def tomcat_support_id(version)
      "tomcat-buildpack-support-#{version}"
    end

    def link_application
      system "rm -rf #{root}"
      system "mkdir -p #{webapps}"
      system "ln -sfn #{File.join '..', '..'} #{root}"
    end

    def link_libs
      libs = ContainerUtils.libs(@app_dir, @lib_directory)

      if libs
        FileUtils.mkdir_p(web_inf_lib) unless File.exists?(web_inf_lib)
        libs.each { |lib| system "ln -sfn #{File.join '..', '..', lib} #{web_inf_lib}" }
      end
    end

    def root
      File.join webapps, 'ROOT'
    end

    def support_jar_name(version)
      "#{tomcat_support_id version}.jar"
    end

    def tomcat_home
      File.join @app_dir, TOMCAT_HOME
    end

    def webapps
      File.join tomcat_home, 'webapps'
    end

    def web_inf_lib
      File.join root, 'WEB-INF', 'lib'
    end

    def self.web_inf?(app_dir)
      File.exists? File.join(app_dir, WEB_INF_DIRECTORY)
    end

  end

end
