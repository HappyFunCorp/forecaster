require 'faraday'
require 'json'
require 'dotenv/load'

class Harvest
  def initialize
    if ENV['HARVEST_TOKEN'].nil? || ENV['HARVEST_ID'].nil?
      throw "Set HARVEST_TOKEN and HARVEST_ID in .env"
    end
  end
  
  def headers
    {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Harvest-Account-ID" => ENV['HARVEST_ID']
    }
  end

  def paged_data url, headers, query = {}
    next_page = 1
    while next_page
      puts "#{url}: page #{next_page}"

      query["page"] = next_page

      response = Faraday.get( url, query, headers )
      next_page = nil

      if response.status != 200
        throw "#{url} -> #{response.status}: #{response.body}"
      end

      data = JSON.parse( response.body )

      yield data

      next_page = data['next_page']
    end
  end

  def users
    values = []

    keys = [ "id", "is_active", "first_name", "last_name", "email", "telephone", "timezone", "is_contractor", "is_admin", "is_project_manager", "created_at", "weekly_capacity", "default_hourly_rate", "cost_rate", "avatar_url" ]
    values << keys.dup
    values.first << 'roles'
    
    paged_data( "https://api.harvestapp.com/v2/users", headers ) do |data|
      data['users'].each do |user|
        user_row = keys.collect { |x| user[x] }
        user_row.append user['roles'].join(",")

        values << user_row
      end
    end
    values
  end

  def projects
    values = []

    keys = ["id", "client", "name", "is_active", "is_billable", "is_fixed_fee", "bill_by", "budget", "budget_by", "budget_is_monthly", "cost_budget", "fee", "notes", "starts_on", "ends_on", "created_at" ]
    values << keys
    
    paged_data( "https://api.harvestapp.com/v2/projects", headers ) do |data|
      data['projects'].each do |project|
        values << keys.collect { |x| project[x] }
        values.last[1] = values.last[1]["name"]
      end
    end
    values
  end

  def user_assignments query = {}
    values = []

    values << ["project_id", "project_name", "user_id", "name", "use_default_rates", "hourly_rate" ]

    paged_data( "https://api.harvestapp.com/v2/user_assignments", headers, query ) do |data|
      data['user_assignments'].each do |ua|
        values << [ua['project']['id'], ua['project']['name'], ua['user']['id'], ua['user']['name'], ua['use_default_rates'], ua['hourly_rate']]
      end
    end

    values
  end

  def task_assignments query = {}
    values = []
    values << [ 'project_id', 'project_name', 'billable', 'task_name', 'hourly_rate']

    paged_data( "https://api.harvestapp.com/v2/task_assignments", headers, query ) do |data|
      data['task_assignments'].each do |ua|
        values << [ua['project']['id'], ua['project']['name'], ua['billable'], ua['task']['name'], ua['hourly_rate']]
      end
    end

    values
  end
end

if __FILE__ == $0
  require 'pp'

  pp Harvest.new.users
end
      
