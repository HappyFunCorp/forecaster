#!/usr/env ruby
require 'faraday'
require 'JSON'
require 'dotenv/load'
require 'date'
require 'csv'
require 'pp'

def start_of_this_week
  now = Date.today
  sunday = now - now.wday
end

class Harvest
  def user_assignments( file = 'data/user_assignments.csv' )
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Harvest-Account-ID" => ENV['HARVEST_ID']
    }

    CSV.open( file, "wb" ) do |out|
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

  def task_assignments( file = 'data/task_assignments.csv' )
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Harvest-Account-ID" => ENV['HARVEST_ID']
    }

    CSV.open( file, "wb" ) do |out|
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

class Forecast
  def assignments( week = start_of_this_week )
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Forecast-Account-ID" => ENV['FORECAST_ID']
    }

    filter = {
      start_date: week.strftime( "%Y-%m-%d" ),
      end_date: (week + 7).strftime( "%Y-%m-%d"),
      state: "active"
    }

    puts "Loading data from forecast"
    response = Faraday.get( "https://api.forecastapp.com/assignments", filter, headers )

    if response.status == 200
      data = JSON.parse( response.body )

      return data
    else
      throw "#{response.status}: #{response.body}"
    end
  end

  def assignments_to_csv( week = start_of_this_week, file = "data/assignments_#{week}.csv" )
    puts "Saving data into #{file}"
    CSV.open( file, "wb" ) do |out|
      out << ["project_id", "person_id", "allocation"]
      assignments( week )["assignments"].each do |a|
        # Not really sure where 720 comes from but if empiracally this is what makes it look
        # like what you see in the site itself
        out << [ a['project_id'], a['person_id'], a["allocation"].to_i / 720  ]
      end
    end
  end

  def people
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Forecast-Account-ID" => ENV['FORECAST_ID']
    }

    puts "Looking up forecast user data"

    response = Faraday.get( "https://api.forecastapp.com/people", {}, headers )

    if response.status != 200
      throw "#{response.status}: #{response.body}"
    end

    return JSON.parse( response.body )
  end

  def people_to_csv(file = "data/forecast_people.csv")
    puts "Saving data into #{file}"
    CSV.open( file, "wb" ) do |out|
      out << ["person_id", "harvest_user_id", "first_name", "last_name", "roles"]
      people["people"].each do |a|
        # Not really sure where 720 comes from but if empiracally this is what makes it look
        # like what you see in the site itself
        out << [ a['id'], a['harvest_user_id'], a["first_name"], a["last_name"], a["roles"].join( " ") ]
      end
    end
  end


  def projects
    headers = {
      "Authorization" => "Bearer #{ENV['HARVEST_TOKEN']}",
      "Forecast-Account-ID" => ENV['FORECAST_ID']
    }

    puts "Looking up forecast user data"

    response = Faraday.get( "https://api.forecastapp.com/projects", {}, headers )

    if response.status != 200
      throw "#{response.status}: #{response.body}"
    end

    return JSON.parse( response.body )
  end

  def projects_to_csv(file = "data/forecast_projects.csv")
    puts "Saving data into #{file}"

    CSV.open( file, "wb" ) do |out|
      out << ["project_id", "harvest_id", "name"]
      projects["projects"].each do |a|
        # Not really sure where 720 comes from but if empiracally this is what makes it look
        # like what you see in the site itself
        out << [ a['id'], a['harvest_id'], a["name"]]
      end
    end
  end
end

FileUtils.mkdir_p "data"

if !File.exists? "data/forecast_people.csv"
  Forecast.new.people_to_csv
end

if !File.exists? "data/forecast_projects.csv"
  Forecast.new.projects_to_csv
end


if !File.exists? "data/assignments_#{start_of_this_week}.csv"
  Forecast.new.assignments_to_csv
end


if !File.exists? "data/user_assignments.csv"
  Harvest.new.user_assignments
end

if !File.exists? "data/task_assignments.csv"
  Harvest.new.task_assignments
end
