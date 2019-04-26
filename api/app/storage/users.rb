# THINKME: Want an agency ref type?  Type:ID sort of thing

class Users < BaseStorage

  def self.page(page, page_size)
    permission_dataset = db[:user]
                           .left_join(:agency_user, Sequel[:agency_user][:user_id] => Sequel[:user][:id])

    unless Ctx.get.permissions.is_admin?
      current_location = Ctx.get.current_location
      if Ctx.get.permissions.is_senior_agency_admin?(current_location.agency_id)
        permission_dataset = permission_dataset
                    .filter(Sequel[:agency_user][:agency_id] => current_location.agency_id)
                    .filter(Sequel[:agency_user][:agency_location_id] => current_location.id)

      elsif Ctx.get.permissions.is_agency_admin?(current_location.agency_id, current_location.id)
        permission_dataset = permission_dataset
                    .filter(Sequel[:agency_user][:agency_id] => current_location.agency_id)
                    .filter(Sequel[:agency_user][:agency_location_id] => current_location.id)

      else
        raise "Insufficient Privileges"
      end
    end

    users_visible_to_current_user = db[:user].filter(:id => permission_dataset.select(Sequel[:user][:id]))

    max_page = (users_visible_to_current_user.count / page_size.to_f).ceil

    users_visible_to_current_user = users_visible_to_current_user.limit(page_size, page * page_size)

    agency_permissions_by_user_id = {}
    aspace_agency_ids_to_resolve = []

    permission_dataset = permission_dataset
                           .join(:agency, Sequel[:agency][:id] => Sequel[:agency_user][:agency_id])
                           .join(:agency_location, Sequel[:agency_location][:id] => Sequel[:agency_user][:agency_location_id])

    permission_dataset
      .select(Sequel[:agency_user][:user_id],
              Sequel.as(Sequel[:agency_user][:role], :role),
              Sequel.as(Sequel[:agency_user][:agency_location_id], :agency_location_id),
              Sequel.as(Sequel[:agency_location][:name], :agency_location_label),
              Sequel[:agency][:aspace_agency_id])
      .each do |row|
      # FIXME ref business
      agency_ref = "agent_corporate_entity:#{row[:aspace_agency_id]}"
      agency_permissions_by_user_id[row[:user_id]] ||= []
      agency_permissions_by_user_id[row[:user_id]] << [agency_ref, row[:role], row[:agency_location_id], row[:agency_location_label]]
      aspace_agency_ids_to_resolve << row[:aspace_agency_id]
    end

    agencies_by_agency_ref = {}

    AspaceDB.open do |aspace_db|
      aspace_db[:agent_corporate_entity]
        .join(:name_corporate_entity, Sequel[:agent_corporate_entity][:id] => Sequel[:name_corporate_entity][:agent_corporate_entity_id])
        .filter(Sequel[:name_corporate_entity][:authorized] => 1)
        .filter(Sequel[:agent_corporate_entity][:id] => aspace_agency_ids_to_resolve)
        .select(Sequel[:agent_corporate_entity][:id],
                Sequel[:name_corporate_entity][:sort_name]).each do |row|
        # FIXME ref business
        agencies_by_agency_ref['agent_corporate_entity' + ':' + row[:id].to_s] = Agency.from_row(row)
      end
    end

    PagedResults.new(users_visible_to_current_user.select_all(:user).map {|r| User.from_row(r, agency_permissions_by_user_id.fetch(r[:id], []).map {|agency_ref, role, location_id, location_label| [ agencies_by_agency_ref.fetch(agency_ref), role, location_label ]})},
                   page,
                   max_page)
  end

  def self.user_exists?(username)
    !!db[:user][:username => username]
  end

  # Returns ID of new user
  def self.create_user(username, name)
    db[:user].insert(:username => username,
                     :name => name,
                     :admin => 0,
                     :create_time => java.lang.System.currentTimeMillis,
                     :modified_time => java.lang.System.currentTimeMillis)
  end

  def self.create_admin_user(username, name)
    db[:user].insert(:username => username,
                     :name => name,
                     :admin => 1,
                     :create_time => java.lang.System.currentTimeMillis,
                     :modified_time => java.lang.System.currentTimeMillis)
  end

  def self.update_user(user_id, username, name, is_admin)
    db[:user]
      .filter(:id => user_id)
      .update(:username => username,
              :name => name,
              :admin => is_admin ? 1 : 0,
              :modified_time => java.lang.System.currentTimeMillis)
  end

  def self.id_for_username(username)
    db[:user][:username => username][:id]
  end

  def self.update_from_dto(user)
    user.validate!
    return if user.has_errors?

    # check for uniqueness
    user_for_username = db[:user][:username => user.username]
    if user_for_username.nil? || user_for_username[:id] == Integer(user.id)
      update_user(user.id, user.username, user.name, user.is_admin?)

      # FIXME what to do about user_agency.mtime? currently clear_roles drops create_time
      if Ctx.get.permissions.is_admin? || Ctx.get.permissions.is_senior_agency_admin?(Ctx.get.current_location.agency_id)
        Permissions.clear_roles(user.id)

        user.agencies.each do |user_agency|
          agency_ref = user_agency.fetch('id')
          role = user_agency.fetch('role')
          location_id = user_agency['location_id']
          permissions = Array(user_agency['permission'])

          # FIXME ref
          (_, aspace_agency_id) = agency_ref.split(':')

          agency_id = Agencies.get_or_create_for_aspace_agency_id(aspace_agency_id)

          if role == 'SENIOR_AGENCY_ADMIN'
            Permissions.add_agency_senior_admin(user.id, agency_id)
          elsif role == 'AGENCY_ADMIN'
            Permissions.add_agency_admin(user.id, agency_id, location_id, permissions)
          elsif role == 'AGENCY_CONTACT'
            Permissions.add_agency_contact(user.id, agency_id, location_id, permissions)
          end
        end
      else
        # ensure permissions set by more senior user are not lost
        # FIXME clean this up
        user_agency = user.agencies.first
        agency_ref = user_agency.fetch('id')
        # FIXME ref
        (_, aspace_agency_id) = agency_ref.split(':')
        agency_id = Agencies.get_or_create_for_aspace_agency_id(aspace_agency_id)
        role = user_agency.fetch('role')
        location_id = user_agency['location_id']
        permissions = Array(user_agency['permission'])

        current_permissions = Permissions.permissions_for_agency_user(user.id, agency_id, location_id)

        permissions += (current_permissions - ['allow_transfers', 'allow_file_issue'])

        Permissions.clear_roles(user.id)

        if role == 'AGENCY_ADMIN'
          Permissions.add_agency_admin(user.id, agency_id, location_id, permissions)
        elsif role == 'AGENCY_CONTACT'
          Permissions.add_agency_contact(user.id, agency_id, location_id, permissions)
        end
      end

      unless user.password.empty?
        DBAuth.set_user_password(user.id, user.password)
      end
    else
      user.add_error('username', 'already in use')
    end
  end

  def self.create_from_dto(user)
    user.validate!
    return if user.has_errors?

    # check for uniqueness
    if db[:user][:username => user.username].nil?
      user_id = if user.is_admin?
                  self.create_admin_user(user.username, user.name)
                else
                  self.create_user(user.username, user.name)
                end

      user.agencies.each do |user_agency|
        agency_ref = user_agency.fetch('id')
        role = user_agency.fetch('role')
        location_id = user_agency['location_id']
        permissions = Array(user_agency['permission'])

        # FIXME ref
        (_, aspace_agency_id) = agency_ref.split(':')

        agency_id = Agencies.get_or_create_for_aspace_agency_id(aspace_agency_id)

        if role == 'SENIOR_AGENCY_ADMIN'
          Permissions.add_agency_senior_admin(user_id, agency_id)
        elsif role == 'AGENCY_ADMIN'
          Permissions.add_agency_admin(user_id, agency_id, location_id, permissions)
        elsif role == 'AGENCY_CONTACT'
          Permissions.add_agency_contact(user_id, agency_id, location_id, permissions)
        end
      end

      DBAuth.set_user_password(user_id, user.password)
    else
      user.add_error('username', 'already in use')
    end
  end

  def self.permissions_for_user(username)
    result = AgencyPermissions.new

    user = db[:user][:username => username]

    # FIXME: we call this is_admin everywhere else...
    result.is_admin = (user[:admin] == 1)

    Permissions.agency_roles_for_user(user[:id]).each do |agency_role|
      result.add_agency_role(agency_role)
    end

    result
  end

  def self.dto_for(username)
    UserUpdateRequest.from_row(
      user = db[:user][:username => username],
      Permissions.agency_roles_for_user(user[:id], with_labels: true))
  end
end
