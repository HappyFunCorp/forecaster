require './harvest'
require './sheets'

class Sync
  def initialize
    @harvest = Harvest.new
    @sheets = GoogleSheets.new

    load_config
    @sheet_id = @config["sheet"]

    if @sheet_id.nil?
      @sheet_id = @sheets.create_spreadsheet( "Roster", ["Dashboard", "People", "Projects", "UserAssignments", "TaskAssignments"] )
      @config["sheet"] = @sheet_id
      save_config
    end
  end

  def load_config
    @config = {}
    if File.exists? 'sheet.json'
      @config = JSON.parse( File.read( 'sheet.json' ) )
    end
  end

  def save_config
    File.open("sheet.json","w") do |f|
      f.write(JSON.pretty_generate(@config))
    end
  end

  def sync_everything
    sync_users
    sync_projects
    sync_user_assignments
    sync_task_assignments
    # TODO    sync_timesheets
    # TODO sync_forecast_projects
    # TODO sync_forecast allocations
    sync_dashboard
  end

  def sync_users
    users = @harvest.users

    letter_range = ("A".."Z").to_a[users.first.length]
    range = "People!A1:#{letter_range}"

    @sheets.update_values @sheet_id, range, users
    @config["harvest_sync_users"] = Time.now
    save_config
  end

  def sync_projects
    data= @harvest.projects

    letter_range = ("A".."Z").to_a[data.first.length]
    range = "Projects!A1:#{letter_range}"

    @sheets.update_values @sheet_id, range, data
    @config["harvest_sync_projects"] = Time.now
    save_config
  end

  def sync_user_assignments
    data = @harvest.user_assignments( { is_active: true } )
    letter_range = ("A".."Z").to_a[data.first.length]
    range = "UserAssignments!A1:#{letter_range}"

    @sheets.update_values @sheet_id, range, data
    @config["harvest_sync_assignments"] = Time.now
    save_config
  end    

  def sync_task_assignments
    data = @harvest.task_assignments( { is_active: true } )
    letter_range = ("A".."Z").to_a[data.first.length]
    range = "TaskAssignments!A1:#{letter_range}"

    @sheets.update_values @sheet_id, range, data
    @config["harvest_sync_tasks"] = Time.now
    save_config
  end    

  def sync_dashboard
    dashboard_values = []
    dashboard_values << [ 'Projects', "" ]
    dashboard_values << [ 'Active Projects', '=countif( Projects!D:D, "=TRUE" )' ]
    dashboard_values << [ 'Active NonBillable Projects', '=countifs( Projects!D:D, "=TRUE", Projects!E:E, "=FALSE" )', "This should similar to HFC Projects count" ]
    dashboard_values << [ 'HFC Projects', '=countifs( Projects!B:B, "=HappyFunCorp", Projects!D:D, "=TRUE" )' ]
    dashboard_values << [ 'Active No Start Date', '=countifs( Projects!D:D, "=TRUE", Projects!N:N, "<>" )' ]
    dashboard_values << [ 'Active No End Date', '=countifs( Projects!D:D, "=TRUE", Projects!O:O, "<>" )' ]

    dashboard_values << ['People', ""]
    
    dashboard_values << [ 'Active Harvest Users', '=countif( People!B:B, "=TRUE" )' ]
    dashboard_values << [ 'Contractors', '=countifs(People!B:B, "=TRUE", People!H:H, "=TRUE")']
    dashboard_values << [ 'Project Managers', '=countifs(People!B:B, "=TRUE", People!J:J, "=TRUE")', "Seems incorrect"]

    dashboard_values << ['Sync Times', ""]
    dashboard_values << [ 'Harvest Users', @config["harvest_sync_users"].to_s ]
    dashboard_values << [ 'Harvest Projects', @config["harvest_sync_projects"].to_s ]
    dashboard_values << [ 'Harvest User Assignments', @config["harvest_sync_assignments"].to_s ]
    dashboard_values << [ 'Harvest Task Assignments', @config["harvest_sync_tasks"].to_s ]
    
    @sheets.update_values @sheet_id, "Dashboard!A1:C", dashboard_values
  end
end

Sync.new.sync_everything
