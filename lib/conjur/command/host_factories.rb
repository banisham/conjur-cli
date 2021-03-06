#
# Copyright (C) 2014 Conjur Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

class Conjur::Command::HostFactories < Conjur::Command
  desc "Manage host factories"

  command :hostfactory do |hf|
    hf.desc "Operations on tokens"
    hf.long_desc <<-DESC
This command creates one or more identical tokens. A token is always created with an 
expiration time, which by default is 1 hour from now. The expiration time can be customized
with command arguments specifying the number of minutes, hours, days for which the token
will be valid.

By default, this command creates one token. Optionally, it can be used to create multiple identical tokens.
    DESC
    hf.command :tokens do |tokens|
      
      tokens.desc "Create one or more tokens"
      tokens.arg_name "hostfactory"
      tokens.command :create do |c|
        c.arg_name "duration in minutes"
        c.desc "Number of minutes from now in which the token will expire"
        c.flag [:"duration-minutes"]

        c.arg_name "duration in hours"
        c.desc "Number of hours from now in which the token will expire"
        c.flag [:"duration-hours"]
          
        c.arg_name "duration in days"
        c.desc "Number of days from now in which the token will expire"
        c.flag [:"duration-days"]
        
        c.arg_name "count"
        c.desc "Number of identical tokens to create"
        c.flag [:c, :count]

        c.arg_name "cidr"
        c.desc "A comma-delimited list of CIDR addresses to restrict token to (optional)"
        c.flag [:cidr]

        c.action do |global_options,options,args|
          id = require_arg(args, 'hostfactory')

          duration = 0
          %w(duration-minutes duration-hours duration-days).each do |d|
            if t = options[d.to_sym]
              duration += t.to_i.send(d.split('-')[-1])
            end
          end
          if duration == 0
            duration = 1.hour
          end
          expiration = Time.now + duration
          count = (options[:count] || 1).to_i
          
          cidr = format_cidr(options.delete(:cidr))

          tokens = api.resource(full_resource_id("host_factory:#{id}")).create_tokens expiration, count: count, cidr: cidr
          display tokens.map(&:to_json)
        end
      end

      tokens.desc "Revoke (delete) a token"
      tokens.arg_name "token"
      tokens.command :revoke do |c|
        c.action do |global_options,options,args|
          token = require_arg(args, 'token')
          
          api.revoke_host_factory_token token
          puts "Token revoked"
        end
      end
    end

    hf.desc "Operations on hosts"
    hf.command :hosts do |hosts|
      hosts.desc "Use a token to create a host"
      hosts.arg_name "token host-id"
      hosts.command :create do |c|
        c.action do |global_options,options,args|
          token = require_arg(args, 'token')
          id = require_arg(args, 'host-id')

          host = Conjur::API.host_factory_create_host token, id, options
          display host
        end
      end
    end
  end

  def self.format_cidr(cidr)
    case cidr
    when 'all'
      []
    when nil
      nil
    else
      cidr.split(',').each {|x| x.strip!}
    end
  end
end
