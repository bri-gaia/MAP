class MAPTheApp < Sinatra::Base

  Endpoint.get('/') do
    if Ctx.session[:username]
      # These tags get escaped...
      Templates.emit_with_layout(:hello, {
                                   :name => Ctx.session[:username],
                                   :agency => Ctx.client.get_current_agency,
                                   :location => Ctx.get.current_location
                                 },
                                 :layout, title: "Welcome", context: 'home')
    else
      Templates.emit_with_layout(:login, {},
                                 :layout_blank, title: "Please log in")
    end
  end

  Endpoint.get('/js/*')
    .param(:cb, String, "Cachebuster (ignored)", optional: true) do

    filename = request.path.split('/').last

    if JSBundle.has_bundle?(filename)
      send_file JSBundle.filename_for_bundle(filename)
    elsif filename == 'vue.js'
      if MAPTheApp.production?
        send_file File.join('ts/node_modules/vue/dist/vue.min.js')
      else
        send_file File.join('ts/node_modules/vue/dist/vue.js')
      end
    elsif filename == 'vue-resource.js'
      send_file File.join('ts/node_modules/vue-resource/dist/vue-resource.min.js')
    elsif File.exist?(file = File.join('js', filename))
      send_file file
    elsif File.exist?(file = File.join('buildjs', filename))
      send_file file
    else
      [404]
    end
  end

  Endpoint.get('/css/*')
    .param(:cb, String, "Cachebuster (ignored)", optional: true) do

    filename = request.path.split('/').last
    if File.exist?(file = File.join('css', filename))
      send_file file
    else
      [404]
    end
  end

  Endpoint.get('/webfonts/*') do
    filename = request.path.split('/').last
    if File.exist?(file = File.join('webfonts', filename))
      send_file file
    else
      [404]
    end
  end


  Endpoint.post('/authenticate')
   .param(:username, String, "Username to authenticate")
   .param(:password, String, "Password") do 
    authentication = Ctx.client.authenticate(params[:username], params[:password])

    if authentication.successful?
      session[:api_session_id] = authentication.session_id or raise "WOOT"
      session[:username] = params[:username]

      redirect '/'
    else
      Templates.emit_with_layout(:login, {username: params[:username], message: "Login failed"},
                                 :layout_blank, title: "Please log in")
    end
  end

  Endpoint.get('/users')
    .param(:page, Integer, "Page to return", optional: true) do
      Templates.emit_with_layout(:users, {paged_users: Ctx.client.users(params[:page] || 0)},
                                 :layout, title: "Users", context: 'users')
  end

  Endpoint.get('/users/new') do
    Templates.emit_with_layout(:user_new, {user: UserUpdateRequest.new},
                               :layout, title: "New User", context: 'users')
  end

  Endpoint.post('/users/create')
    .param(:user, UserUpdateRequest, "The user to create") do

    unless Ctx.permissions.is_admin?
      params[:user].is_admin = false
      if Ctx.permissions.is_senior_agency_admin?
        params[:user].agencies.select! do |agency|
          (agency['location_id'] == Ctx.get.current_location.id) 
        end
      elsif Ctx.permissions.is_agency_admin?
        params[:user].agencies.select! do |agency|
          (agency['location_id'] == Ctx.get.current_location.id) && agency['role'] != 'SENIOR_AGENCY_ADMIN'
        end
      else
        # FIXME
        raise "Insufficient Privileges"
      end
    end

    params[:user].validate!

    Ctx.client.create_user(params[:user]) unless params[:user].has_errors?

    if params[:user].has_errors?
      Templates.emit_with_layout(:user_new, {user: params[:user]},
                                   :layout, title: "New User", context: 'users')
    else
      redirect '/users'
    end
  end

  Endpoint.get('/logout') do
    session[:api_session_id] = nil
    session[:username] = nil

    # [200, "Woot"]
    redirect '/'
  end

  Endpoint.get('/search/agencies')
    .param(:q, String, "Search string") do
    [
      200,
      {'Content-type' => 'text/json'},
      Ctx.client.agency_typeahead(params[:q]).to_json
    ]
  end

  Endpoint.get('/locations')
    .param(:page, Integer, "Page to return", optional: true) do

    Templates.emit_with_layout(:locations, {paged_results: Ctx.client.locations(params[:page] || 0)},
                               :layout, title: "Locations", context: 'locations')
  end

  Endpoint.get('/locations/new') do
    Templates.emit_with_layout(:location_new, {location: AgencyLocationUpdateRequest.new},
                               :layout, title: "New Location", context: 'locations')
  end

  Endpoint.post('/locations/create')
    .param(:location, AgencyLocationUpdateRequest, "The agency location to create") do

    unless Ctx.permissions.is_admin?
        params[:location].agency_ref = Ctx.get.current_location.agency.id
    end

    Ctx.client.create_location(params[:location])

    if params[:location].has_errors?
      Templates.emit_with_layout(:location_new, {location: params[:location]},
                                 :layout, title: "New Location", context: 'locations')
    else
      redirect '/locations'
    end
  end

  Endpoint.get('/linker_data_for_agency')
    .param(:agency_ref, String, "Agency Ref") do
    if Ctx.permissions.is_admin?
      [
        200,
        {'Content-type' => 'text/json'},
        {
          'location_options' => Ctx.client.locations_for_agency(params[:agency_ref]).map(&:to_search_result),
          # FIXME some shared lib?
          'permission_options' => [:allow_transfers, :allow_file_issue, :allow_set_raps, :allow_change_raps, :allow_restricted_access]
        }.to_json
      ]
    else
      [404]
    end
  end

  Endpoint.post('/set-location')
    .param(:agency_id, Integer, "Agency Id")
    .param(:location_id, Integer, "Location Id") do

    Ctx.client.set_location(params[:agency_id], params[:location_id])

    [
      200,
      {'Content-type' => 'text/json'},
      {
        'status' => 'ok'
      }.to_json
    ]
  end

end
