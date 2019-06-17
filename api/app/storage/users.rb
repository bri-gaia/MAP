# THINKME: Want an agency ref type?  Type:ID sort of thing

class Users < BaseStorage

  SORT_OPTIONS = {
    'username_asc' => Sequel.asc(Sequel[:user][:username]),
    'username_desc' => Sequel.desc(Sequel[:user][:username]),
    'name_asc' => Sequel.asc(Sequel[:user][:name]),
    'name_desc' => Sequel.desc(Sequel[:user][:name]),
    'created_asc' => Sequel.asc(Sequel[:user][:create_time]),
    'created_desc' => Sequel.desc(Sequel[:user][:create_time]),
  }

  def self.all(page, page_size, q = nil, agency_ref = nil, role = nil, sort = nil)
    if agency_ref
      (_, aspace_agency_id) = agency_ref.split(':')
      agency_id = db[:agency].filter(aspace_agency_id: aspace_agency_id.to_i).select(:id)
      page(page, page_size, agency_id, nil, q, role, sort)
    else
      page(page, page_size, nil, nil, q, role, sort)
    end
  end

  def self.for_agency(page, page_size, agency_id, q = nil, role = nil, sort = nil)
    page(page, page_size, agency_id, nil, q, role, sort)
  end

  def self.for_agency_location(page, page_size, agency_id, agency_location_id, q = nil, role = nil, sort = nil)
    page(page, page_size, agency_id, agency_location_id, q, role,sort)
  end

  def self.page(page, page_size, agency_id = nil, agency_location_id = nil, q = nil, role = nil, sort = nil)
    permission_dataset = db[:user]
                           .left_join(:agency_user, Sequel[:agency_user][:user_id] => Sequel[:user][:id])

    if agency_id
      permission_dataset = permission_dataset.filter(Sequel[:agency_user][:agency_id] => agency_id)
    end

    if agency_location_id
      permission_dataset = permission_dataset.filter(Sequel[:agency_user][:agency_location_id] => agency_location_id)
    end

    users_visible_to_current_user = db[:user]
                                      .left_join(:agency_user, Sequel[:agency_user][:user_id] => Sequel[:user][:id])
                                      .filter(Sequel[:user][:id] => permission_dataset.select(Sequel[:user][:id]))

    max_page = (users_visible_to_current_user.count / page_size.to_f).ceil

    users_visible_to_current_user = users_visible_to_current_user.limit(page_size, page * page_size)

    users_visible_to_current_user = users_visible_to_current_user.order(Sequel.asc(Sequel[:user][:username]))

    if q
      sanitised = q.downcase.gsub(/[^a-z0-9_\-\. ]/, '_')
      users_visible_to_current_user = users_visible_to_current_user.filter(Sequel.|(Sequel.like(Sequel.function(:lower, Sequel[:user][:username]), "%#{sanitised}%"), Sequel.like(Sequel.function(:lower, Sequel[:user][:name]), "%#{sanitised}%")))
    end


    if role
      users_visible_to_current_user = users_visible_to_current_user.filter(Sequel[:agency_user][:role] => role)
    end

    sort_by = SORT_OPTIONS.fetch(sort, SORT_OPTIONS.fetch('username_asc'));
    users_visible_to_current_user = users_visible_to_current_user.order(sort_by)

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
        agencies_by_agency_ref['agent_corporate_entity' + ':' + row[:id].to_s] = Agency.from_row(row)
      end
    end

    results = users_visible_to_current_user
               .select_all(:user)
                .distinct
               .map do |row|
                 permissions = agency_permissions_by_user_id.fetch(row[:id], []).map {|agency_ref, role, location_id, location_label| [ agencies_by_agency_ref.fetch(agency_ref), role, location_label ]}
                 User.from_row(row, permissions)
               end

    PagedResults.new(results, page, max_page)
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

  def self.update_current_user(user_id, name, lock_version)
    updated = db[:user]
                .filter(id: user_id)
                .filter(lock_version: lock_version)
                .update(name: name,
                        lock_version: lock_version + 1,
                        modified_time: java.lang.System.currentTimeMillis)

    raise StaleRecordException.new if updated == 0
  end


  def self.update_user(user_id, username, name, is_admin, is_inactive, lock_version)
    updated = db[:user]
                .filter(id: user_id)
                .filter(lock_version: lock_version)
                .update(username: username,
                        name: name,
                        admin: is_admin ? 1 : 0,
                        inactive: is_inactive ? 1 : 0,
                        lock_version: lock_version + 1,
                        modified_time: java.lang.System.currentTimeMillis)

    raise StaleRecordException.new if updated == 0
  end

  def self.id_for_username(username)
    db[:user][:username => username][:id]
  end

  def self.update_from_dto(user)
    # check for uniqueness
    user_for_username = db[:user][:username => user.fetch('username')]

    if user_for_username.nil? || user_for_username[:id] == Integer(user.fetch('id'))
      if user.fetch('username') == Ctx.username
        update_current_user(user.fetch('id'),
                            user.fetch('name'),
                            user.fetch('lock_version'))
      else
        update_user(user.fetch('id'),
                    user.fetch('username'),
                    user.fetch('name'),
                    user.fetch('is_admin'),
                    user.fetch('is_inactive'),
                    user.fetch('lock_version'))

        # FIXME what to do about user_agency.mtime? currently clear_roles drops create_time
        if Ctx.get.permissions.is_admin? || Ctx.get.permissions.is_senior_agency_admin?(Ctx.get.current_location.agency_id)
          Permissions.clear_roles(user.fetch('id'))

          unless user.fetch('is_admin')
            user.fetch('agency_roles').each do |agency_role|
              agency_ref = agency_role.fetch('agency_ref')
              role = agency_role.fetch('role')
              location_id = agency_role.fetch('agency_location_id', nil)
              permissions = agency_role.fetch('permissions')

              (_, aspace_agency_id) = agency_ref.split(':')
              agency_id = Agencies.get_or_create_for_aspace_agency_id(aspace_agency_id)

              if location_id.nil? || location_id == ''
                location_id = Locations.locations_for_agency(aspace_agency_id).first.id
              end

              if role == 'SENIOR_AGENCY_ADMIN'
                Permissions.add_agency_senior_admin(user.fetch('id'), agency_id)
              elsif role == 'AGENCY_ADMIN'
                Permissions.add_agency_admin(user.fetch('id'), agency_id, location_id, permissions)
              elsif role == 'AGENCY_CONTACT'
                Permissions.add_agency_contact(user.fetch('id'), agency_id, location_id, permissions)
              end
            end
          end
        else
          # ensure permissions set by more senior user are not lost
          agency_role = user.fetch('agency_roles').first
          agency_ref = agency_role.fetch('agency_ref')

          (_, aspace_agency_id) = agency_ref.split(':')
          agency_id = Agencies.get_or_create_for_aspace_agency_id(aspace_agency_id)
          role = agency_role.fetch('role')
          location_id = agency_role.fetch('agency_location_id')
          permissions = agency_role.fetch('permissions')

          current_permissions = Permissions.permissions_for_agency_user(user.fetch('id'), agency_id, location_id)

          permissions += (current_permissions - ['allow_transfers', 'allow_file_issue'])

          Permissions.clear_roles(user.fetch('id'))

          if role == 'AGENCY_ADMIN'
            Permissions.add_agency_admin(user.fetch('id'), agency_id, location_id, permissions)
          elsif role == 'AGENCY_CONTACT'
            Permissions.add_agency_contact(user.fetch('id'), agency_id, location_id, permissions)
          end
        end
      end

      unless user.fetch('password').empty?
        DBAuth.set_user_password(user.fetch('id'), user.fetch('password'))
      end

      []
    else
      [{code: "UNIQUE_CONSTRAINT", field: 'username'}]
    end
  end

  def self.create_from_dto(user)
    # check for uniqueness
    if db[:user][:username => user.fetch('username')].nil?
      user_id = if user.fetch('is_admin')
                  self.create_admin_user(user.fetch('username'), user.fetch('name'))
                else
                  self.create_user(user.fetch('username'), user.fetch('username'))
                end

      unless user.fetch('is_admin')
        user.fetch('agency_roles', []).each do |agency_role|
          agency_ref = agency_role.fetch('agency_ref')
          role = agency_role.fetch('role')
          location_id = agency_role.fetch('agency_location_id', nil)
          permissions = agency_role.fetch('permissions')

          (_, aspace_agency_id) = agency_ref.split(':')
          agency_id = Agencies.get_or_create_for_aspace_agency_id(aspace_agency_id)

          if location_id.nil? || location_id == ''
            location_id = Locations.locations_for_agency(aspace_agency_id).first.id
          end

          if role == 'SENIOR_AGENCY_ADMIN'
            Permissions.add_agency_senior_admin(user_id, agency_id)
          elsif role == 'AGENCY_ADMIN'
            Permissions.add_agency_admin(user_id, agency_id, location_id, permissions)
          elsif role == 'AGENCY_CONTACT'
            Permissions.add_agency_contact(user_id, agency_id, location_id, permissions)
          end
        end
      end

      DBAuth.set_user_password(user_id, user.fetch('password'))

      []
    else
      [{code: "UNIQUE_CONSTRAINT", field: 'username'}]
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
    user = db[:user][:username => username]

    UserDTO.from_row(
      user,
      Permissions.agency_roles_for_user(user[:id], with_labels: true))
  end

  def self.validate_roles(dto)
      errors = []

      if Ctx.get.permissions.is_admin?
        # No dramas
      elsif Ctx.get.permissions.is_senior_agency_admin?(Ctx.get.current_location.agency_id)
        dto.fetch('agency_roles').each do |agency_role|
          if agency_role.fetch('agency_ref') != Ctx.get.current_location.agency_ref
            errors << {code: "AGENCY_MISMATCH", field: 'agency_roles'}
          end
        end
      elsif Ctx.get.permissions.is_agency_admin?(Ctx.get.current_location.agency_id, Ctx.get.current_location.id)
        dto.fetch('agency_roles').each do |agency_role|
          if agency_role.fetch('agency_ref') != Ctx.get.current_location.agency_ref
            errors << {code: "AGENCY_MISMATCH", field: 'agency_roles'}
          elsif agency_role.fetch('agency_location_id') != Ctx.get.current_location.id
            errors << {code: "AGENCY_LOCATION_MISMATCH", field: 'agency_roles'}
          end
          if agency_role.fetch('role') == 'SENIOR_AGENCY_ADMIN'
            errors << {code: "INSUFFICIENT_PRIVILEGES", field: 'agency_roles'}
          end
        end
      elsif Ctx.username == dto.fetch('username')
        # Permissions are ignored in storage
      else
        errors << {code: "INSUFFICIENT_PRIVILEGES", field: 'agency_roles'}
      end

      errors
  end
end
