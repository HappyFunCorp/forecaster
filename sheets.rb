require "google/apis/sheets_v4"
require "googleauth"
require "googleauth/stores/file_token_store"
require "fileutils"
require "faker"

class GoogleSheets
  OOB_URI = "urn:ietf:wg:oauth:2.0:oob".freeze
  APPLICATION_NAME = "My Google Sheets Application".freeze
  CREDENTIALS_PATH = "credentials.json".freeze
  
  # The file token.yaml stores the user's access and refresh tokens, and is
  # created automatically when the authorization flow completes for the first
  # time.
  TOKEN_PATH = "token.yaml".freeze
  SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS

  def initialize
    # Initialize the API
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.client_options.application_name = APPLICATION_NAME
    @service.authorization = authorize
  end

  def service
    @service
  end

  ##
  # Ensure valid credentials, either by restoring from the saved credentials
  # files or intitiating an OAuth2 authorization. If authorization is required,
  # the user's default browser will be launched to approve the request.
  #
  # @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
  def authorize
    client_id = Google::Auth::ClientId.from_file CREDENTIALS_PATH
    token_store = Google::Auth::Stores::FileTokenStore.new file: TOKEN_PATH
    authorizer = Google::Auth::UserAuthorizer.new client_id, SCOPE, token_store
    user_id = "default"
    credentials = authorizer.get_credentials user_id
    if credentials.nil?
      url = authorizer.get_authorization_url base_url: OOB_URI
      puts "Open the following URL in the browser and enter the " \
           "resulting code after authorization:\n" + url
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id, code: code, base_url: OOB_URI
      )
    end
    credentials
  end

  def read_values( spreadsheet_id, range )
    service.get_spreadsheet_values spreadsheet_id, range
  end

  def print_values( spreadsheet_id, range )
    response = read_values spreadsheet_id, range
    if response.values.nil?
      puts "No data found."
    else
      response.values.each do |row|
        puts row.join( "\t" )
      end
    end
  end

  def create_spreadsheet( name, sheets = ['Sheet1'] )
    spreadsheet = {
      properties: {
        title: name
      },
      sheets: sheets.collect { |sheet| {properties: {title: sheet}} }
    }
    spreadsheet = service.create_spreadsheet(spreadsheet,
                                             fields: 'spreadsheetId')
    puts "Spreadsheet ID: #{spreadsheet.spreadsheet_id}"
    spreadsheet.spreadsheet_id
  end

  def update_values( spreadsheet_id, range, values )
    data = [
      {
        range:  range,
        values: values
      }
    ]
    
    value_range_object = Google::Apis::SheetsV4::ValueRange.new(range:  range,
                                                                values: values)
    result = service.update_spreadsheet_value(spreadsheet_id,
                                              range,
                                              value_range_object,
                                              value_input_option: "USER_ENTERED" )
    puts "#{result.updated_cells} cells updated."

    result
  end
end

if __FILE__ == $0
  #  spreadsheet_id = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"
  #  range = "Class Data!A2:E"

  #  sheets = GoogleSheets.new
  #  sheets.print_values spreadsheet_id, range

  sheets = GoogleSheets.new

  conf = {}
  if File.exists? "sheet.json"
    conf = JSON.parse( File.read( "sheet.json" ) )
  end

  sheet = conf["sheet"]

  if sheet.nil?
    sheet = sheets.create_spreadsheet( "Roster", ["People", "Projects"] )
    conf["sheet"] = sheet
    File.open("sheet.json","w") do |f|
      f.write(JSON.pretty_generate(conf))
    end
  end

  values = [
    [ 'ID', 'Name', 'Address' ]
  ]

  20.times do |id|
    values << [id+1, Faker::Name.name, Faker::Address.city]
  end
  
  sheets.update_values sheet, "People!A1:C", values

  sheets.print_values sheet, "People!A1:C"
end
