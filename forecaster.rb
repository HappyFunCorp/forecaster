#!/usr/env ruby
require 'faraday'
require 'json'
require 'dotenv/load'
require 'date'
require 'csv'
require 'pp'

def start_of_this_week
  now = Date.today
  sunday = now - now.wday
end

class DataSyncer
  DATA_DIR="data"
  def initialize
    FileUtils.mkdir_p "data"
  end

  def datafile_for( key )
    "#{DATA_DIR}/#{key}"
  end

  def needs_refresh? key
    return true if File.exists?( datafile_for( key ) ) && File.size( datafile_for(key)) < 100
    return true if !File.exists?( datafile_for( key ))
    return false
  end

  def load_for_key key, dependants = []
    if needs_refresh? key
      yield key
    end

    data = CSV.read( datafile_for( key ))
    # Remove the header
    data.shift
    data
  end
end

class Harvest < DataSyncer
  def user_assignments
    load_for_key( 'user_assignments.csv' ) do |key|
      user_assignments_to_csv( key )
    end
  end

  def user_assignments_to_csv( key )
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Harvest-Account-ID" => ENV['HARVEST_ID']
    }

    puts "Loading #{key} from harvest"

    CSV.open( datafile_for(key), "wb" ) do |out|
      out << [ 'project_id', 'person_id', 'hourly_rate', 'project_name', 'person_name']
      next_page = 1
      while next_page
        puts "Getting page #{next_page}"

        query = {
          "is_active" => "true",
          "page" => next_page
        }

        response = Faraday.get( "https://api.harvestapp.com/v2/user_assignments", query, headers )

        next_page = nil

        if response.status != 200
          throw "#{response.status}: #{response.body}"
        end

        data = JSON.parse( response.body )

        next_page = data['next_page']

        data['user_assignments'].each do |ua|
          out << [ua['project']['id'], ua['user']['id'], ua['hourly_rate'], ua['project']['name'], ua['user']['name']]
        end
      end
    end
  end

  def task_assignments
    load_for_key 'task_assignments.csv', [] do |key|
      task_assignments_to_csv( key )
    end
  end

  def task_assignments_to_csv( key )
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Harvest-Account-ID" => ENV['HARVEST_ID']
    }

    puts "Loading #{key} from harvest"

    CSV.open( datafile_for(key), "wb" ) do |out|
      out << [ 'project_id', 'project_name', 'billable', 'task_name', 'hourly_rate']
      next_page = 1
      while next_page
        puts "Getting page #{next_page}"

        query = {
          "is_active" => "true",
          "page" => next_page
        }

        response = Faraday.get( "https://api.harvestapp.com/v2/task_assignments", query, headers )

        next_page = nil

        if response.status != 200
          throw "#{response.status}: #{response.body}"
        end

        data = JSON.parse( response.body )

        next_page = data['next_page']

        data['task_assignments'].each do |ua|
          out << [ua['project']['id'], ua['project']['name'], ua['billable'], ua['task']['name'], ua['hourly_rate']]
        end
      end
    end
  end
end

class Forecast < DataSyncer
  def assignments(month)
    key = "assignments_#{month}.csv"

    load_for_key( key ) do
      assignments_to_csv key, month
    end
  end

  def assignments_to_csv( key, month)
    puts "Loading assignments for month: #{month} from forecast"

    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Forecast-Account-ID" => ENV['FORECAST_ID']
    }

    filter = {
      start_date: "2018-#{month-1}-25",
      end_date: "2018-#{month}-24",
      state: "active"
    }

    puts "Loading data from forecast"
    response = Faraday.get( "https://api.forecastapp.com/assignments", filter, headers )

    if response.status == 200
      data = JSON.parse( response.body )

      puts "Saving data into #{key}"
      CSV.open( datafile_for(key), "wb" ) do |out|
        out << ["project_id", "person_id", "allocation"]
        data["assignments"].each do |a|
          # Not really sure where 720 comes from but if empiracally this is what makes it look
          # like what you see in the site itself
          out << [ a['project_id'], a['person_id'], a["allocation"].to_i / 720  ]
        end
      end

      return data
    else
      throw "#{response.status}: #{response.body}"
    end
  end

  def people
    load_for_key( "forecast_people.csv" ) do |key|
      people_to_csv( key )
    end
  end

  def people_to_csv(key)
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Forecast-Account-ID" => ENV['FORECAST_ID']
    }

    puts "Looking up forecast user data"

    response = Faraday.get( "https://api.forecastapp.com/people", {}, headers )

    if response.status != 200
      throw "#{response.status}: #{response.body}"
    end

    data = JSON.parse( response.body )

    puts "Saving user data into #{key}"
    CSV.open( datafile_for(key), "wb" ) do |out|
      out << ["person_id", "harvest_user_id", "first_name", "last_name", "roles"]
      data["people"].each do |a|
        # Not really sure where 720 comes from but if empiracally this is what makes it look
        # like what you see in the site itself
        out << [ a['id'], a['harvest_user_id'], a["first_name"], a["last_name"], a["roles"].join( " ") ]
      end
    end
  end


  def projects
    load_for_key( "forecast_projects.csv" ) do |key|
      projects_to_csv( key )
    end
  end

  def projects_to_csv(key)
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Forecast-Account-ID" => ENV['FORECAST_ID']
    }

    puts "Looking up forecast user data"

    response = Faraday.get( "https://api.forecastapp.com/projects", {}, headers )

    if response.status != 200
      throw "#{response.status}: #{response.body}"
    end

    data = JSON.parse( response.body )

    puts "Saving data into #{key}"

    CSV.open( datafile_for(key), "wb" ) do |out|
      out << ["project_id", "harvest_id", "name"]
      data["projects"].each do |a|
        # Not really sure where 720 comes from but if empiracally this is what makes it look
        # like what you see in the site itself
        out << [ a['id'], a['harvest_id'], a["name"]]
      end
    end
  end
end

class HarvestForecastReport < DataSyncer
  def initialize
    @harvest = Harvest.new
    @forecast = Forecast.new
  end

  def assignments_to_harvest_ids( month )
    key = "assignments_to_harvest_ids_#{month}.csv"
    load_for_key( key, ['forecast_people', 'forecast_projects']) do |key|
      assignments_to_harvest_ids_to_csv key, month
    end
  end

  def assignments_to_harvest_ids_to_csv( key, month )
    people_by_id = {}
    @forecast.people.each do |person|
      people_by_id[person[0]] = person
    end

    projects_by_id = {}
    @forecast.projects.each do |project|
      projects_by_id[project[0]] = project
    end

    CSV.open( datafile_for(key), "wb" ) do |out|
      out << [:forecast_project_id, :harvest_project_id, :harvest_project_name, :harvest_person_id, :hours, :name, :role ]

      @forecast.assignments( month ).each do |assignment|
        project = projects_by_id[assignment[0]]
        person = people_by_id[assignment[1]]
        if !project || !person
          puts "Couldn't find a harvest project id for #{assignment[0]}" if !project
          puts "Couldn't find a harvest person id for #{assignment[1]}" if !person
        else
          out << [
            assignment[0],
            project[1],
            project[2],
            person[1],
            assignment[2],
            person[2],
            person[3],
            person[4]
          ]
        end
      end
    end
  end

  def lookup_rates_by_task_and_role( month )
    key = "rates_by_task_#{month}.csv"
    load_for_key( key, [ 'task_assignments.csv', 'assignments_to_harvest_ids.csv'] ) do |key|
      lookup_rates_by_task_and_role_csv( key, month )
    end
  end

  def lookup_rates_by_task_and_role_csv( key, month )
    project_task_rates = {}
    @harvest.task_assignments.each do |task_assignment|
      project_id = task_assignment[0]
      task = task_assignment[3]
      rate = task_assignment[4]

      # puts "#{task_assignment[1]}: #{task} #{rate}"

      project_task_rates[project_id] ||= {}
      project_task_rates[project_id][task] = rate
    end

    CSV.open( datafile_for( key ), "wb" ) do |out|
      out << [:project_id, :project_name, :person_name, :person_tag, :task, :task_rate, :hours, :subtotal]

      assignments_to_harvest_ids( month ).each do |assignment|
        tasks = project_task_rates[assignment[1]]
        tag = assignment[7]
        first_name = assignment[5]
        name = "#{assignment[5]} #{assignment[6]}"

        if !tasks
          puts "Couldn't find task rates for #{assignment[2]}"
        else
          if name == 'Aaron Brocken'
            tag = 'Product'
          end

          role = tasks.keys.select { |x| x =~ /#{tag}/ }

          if role.length == 0 && name == 'Leah Garber'
            role = tasks.keys.select { |x| x=~ /QA/ }
          end

          if role.length == 0 && (tag == 'Production' || tag == 'Product')
            role = tasks.keys.select { |x| x=~ /Project/ }
          end

          if role.length == 0 && (tag == 'Engineering')
            role = tasks.keys.select { |x| x=~ /Development/ }
          end

          if role.length == 0 && (tag == 'Development')
            role = tasks.keys.select { |x| x=~ /Engineering/ }
          end

          # Maybe they are called out specifically by their name
          if role.length > 1
            new_role = tasks.keys.select { |x| x =~ /#{first_name}/ }
            role = new_role if new_role.length == 1
          end

          # Specific hacks
          if role.length > 1
            if first_name == 'Hannah'
              role = ['Engineering (US)']
            end

            if first_name == 'Ravi'
              role = ['Rails Engineering']
            end

            if first_name == 'Tales'
              role = ['Android Engineering']
            end

            if first_name == 'Peter'
              role = ['iOS Engineering']
            end

            if (first_name == 'Patrick') || (first_name == 'Jeff')
              role = ['Engineering (US)']
            end

            if (first_name == 'Fabio') || (first_name == 'Tarun')
              role = ['Engineering (international or local)']
            end

            if first_name == 'Puneet'
              role = ['Back-end Engineering']
            end

            if first_name == 'Kristopher'
              role = ['React Engineering']
            end

            # Get rid of "Guiding Principals"
            role = role.select { |x| !(x =~ /Guiding/)}
          end

          if role.length == 0
            puts "No Match: #{assignment[2]}: #{name}: Looking for #{tag} in #{tasks.keys.join( ", ")}"
            puts
          elsif role.length > 1
            puts "Multi match: #{assignment[2]}: #{name}: Looking for #{tag} in #{tasks.keys.join( ", ")}"
            puts "More than one tag matched #{role.join(", ")}"
            puts
          else
            out << [
              assignment[1],
              assignment[2],
              name,
              assignment[7],
              role.first,
              tasks[role.first],
              assignment[4],
              tasks[role.first].to_i * assignment[4].to_i
            ]
          end
        end
      end
    end
  end
end

# Forecast.new.link_harvest_ids_to_forecast
HarvestForecastReport.new.lookup_rates_by_task_and_role Date.today.month
HarvestForecastReport.new.lookup_rates_by_task_and_role Date.today.month+1
