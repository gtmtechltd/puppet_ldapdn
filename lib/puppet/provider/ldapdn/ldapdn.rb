require 'puppet/provider'
require 'tempfile'

Puppet::Type.type(:ldapdn).provide :ldapdn do
  desc ""

  commands :ldapmodifycmd => "/usr/bin/ldapmodify"
  commands :ldapaddcmd => "/usr/bin/ldapadd"
  commands :ldapsearchcmd => "/usr/bin/ldapsearch"

  def create()
    ldap_apply_work
  end

  def destroy()
    ldap_apply_work
  end

  def exists?()
    @work_to_do = ldap_work_to_do(parse_attributes)

    # This is a bit of a butchery of an exists? method which is designed to return yes or no,
    # Whereas we are editing a multi-faceted record, and it might be in a semi-desired state.
    # However, as I want to still use the ensure() param, I will have to live within its rules

    if @work_to_do.empty?
      true if resource[:ensure] == :present
      false if resource[:ensure] == :absent
    else
      false if resource[:ensure] == :present
      true if resource[:ensure] == :absent
    end

  end

  def parse_attributes

    ldap_attributes = {}
    Array(resource[:attributes]).each do |asserted_attribute|
      key,value = asserted_attribute.split(':', 2)
      ldap_attributes[key] = [] if ldap_attributes[key].nil?
      ldap_attributes[key] << value.strip!
    end
    ldap_attributes

  end

  def ldap_apply_work
    @work_to_do.each do |modify_type, modifications|

      modify_record = []
      modify_record << "dn: #{resource[:dn]}"

      modify_record << "changetype: modify" if modify_type == :ldapmodify

      modifications.each do |attribute, instructions|
        add_type="add"
        instructions.each do |instruction|
          case instruction.first
          when :add
            modify_record << "add: #{attribute}" if add_type == "add" and modify_type == :ldapmodify
            modify_record << "#{attribute}: #{instruction.last}"
            modify_record << "-" if modify_type == :ldapmodify
          when :delete
            modify_record << "delete: #{attribute}"
            modify_record << "-"
          when :replace
            modify_record << "replace: #{attribute}" if add_type == "add"
            add_type = "replace"
          end
        end
      end

      ldif = Tempfile.open("ldap_apply_work")
      ldif_file = ldif.path
      ldif.write modify_record.join("\n")
      ldif.close

      cmd = case modify_type
      when :ldapmodify
        :ldapmodifycmd
      when :ldapadd
        :ldapaddcmd
      end

      begin
        command = [command(cmd), "-H", "ldapi:///", "-d", "0", "-f", ldif_file]
        command += resource[:auth_opts] || ["-QY", "EXTERNAL"]
        Puppet.debug("\n\n" + File.open(ldif_file, 'r') { |file| file.read })
        output = execute(command)
        Puppet.debug(output)
      rescue Puppet::ExecutionFailure => ex
        raise Puppet::Error, "Ldap Modify Error:\n\n#{modify_record.join("\n")}\n\nError details:\n#{ex.message}"
      # ensure
        # ldif.unlink
      end

    end

  end

  def ldap_work_to_do(asserted_attributes)
    command = [command(:ldapsearchcmd), "-H", "ldapi:///", "-b", resource[:dn], "-s", "base", "-LLL", "-d", "0"]
    command += resource[:auth_opts] || ["-QY", "EXTERNAL"]
    begin
      ldapsearch_output = execute(command)
      Puppet.debug("ldapdn >>\n#{to_json2(asserted_attributes)}")
      Puppet.debug("ldapsearch >>\n#{ldapsearch_output}")
    rescue Puppet::ExecutionFailure => ex
      if ex.message.scan '/No such object (32)/'
        Puppet.debug("Could not find object: #{resource[:dn]}")
        return {} if resource[:ensure] == :absent
        work_to_do = {}
        asserted_attributes.each do |asserted_key, asserted_values|
          key_work_to_do = []
          asserted_values.each do |asserted_value|
            key_work_to_do << [ :add, asserted_value ]
          end
          work_to_do[asserted_key] = key_work_to_do
        end
        Puppet.debug("WorkToDo: { :ldapadd => #{work_to_do}}")
        return { :ldapadd => work_to_do }
      else
        raise ex
      end
    end

    unique_attributes = resource[:unique_attributes]
    unique_attributes = [] if unique_attributes.nil?

    indifferent_attributes = resource[:indifferent_attributes]
    indifferent_attributes = [] if indifferent_attributes.nil?

    work_to_do = {}
    found_attributes = {}
    found_keys = []

    asserted_attributes.each do |asserted_key, asserted_value|
      work_to_do[asserted_key] = []
      found_attributes[asserted_key] = []
    end

    ldapsearch_output.split(/\r?\n(?!\s)/).each do |line|
      line.gsub!(/[\r\n] /, '')
      line.gsub!(/\r?\n?$/, '')
      current_key,current_value = line.split(/:+ /, 2)
      found_keys << current_key
      if asserted_attributes.key?(current_key)
        Puppet.debug("search() #{current_key}: #{current_value}")
        same_as_an_asserted_value = false
        asserted_attributes[current_key].each do |asserted_value|
          Puppet.debug("check() #{current_key}: #{current_value}  <===>  #{current_key}: #{asserted_value}")
          same_as_an_asserted_value = true if asserted_value == current_value
          same_as_an_asserted_value = true if asserted_value.clone.gsub(/^\{.*?\}/, "") == current_value.clone.gsub(/^\{.*?\}/, "")
        end
        if same_as_an_asserted_value
          Puppet.debug("asserted and found: #{current_key}: #{current_value}")
          work_to_do[current_key] << [ :delete ] if resource[:ensure] == :absent
          found_attributes[current_key] << current_value.clone.gsub(/^\{.*?\}/, "")
        else
          Puppet.debug("not asserted: #{current_key}: #{current_value}")
          work_to_do[current_key] << [ :replace ] if resource[:ensure] == :present \
                                                 and unique_attributes.include?(current_key) \
                                                 and !indifferent_attributes.include?(current_key)
        end
      end
    end

    asserted_attributes.each do |asserted_key, asserted_values|
      asserted_values.each do |asserted_value|

        Puppet.debug("assert() #{asserted_key}: #{asserted_value}")

        if resource[:ensure] == :present
          work_to_do[asserted_key] << [ :add, asserted_value ] unless found_attributes[ asserted_key ].include?(asserted_value.clone.gsub(/^\{.*?\}/, "")) \
                                                                   or (found_keys.include?(asserted_key) and indifferent_attributes.include?(asserted_key))
        end

      end
    end

    work_to_do.delete_if {|key, operations| operations.empty?}

    if work_to_do.empty?
      Puppet.debug("conclusion: nothing to do")
      {}
    else
      Puppet.debug("conclusion: work to do: #{to_json2(work_to_do)}")
      { :ldapmodify => work_to_do }
    end

  end


  def to_json2(stringin)

    case stringin.class.to_s
    when "String"
      return "'" + stringin + "'"
    when "Array"
      x = []
      stringin.each do |term|
        x << to_json2(term)
      end
      return "[ " + x.join(', ') + " ]"
    when "Hash"
      x = []
      stringin.each do |key, value|
        x << [to_json2(key), to_json2(value)]
      end
      return "{ " + x.collect {|k| k.first.to_s + " => " + k.last.to_s}.join(', ') + " }"
    when "Symbol"
      return ":" + stringin.to_s
    else
      return "!OBJ(" + stringin.class.to_s + ":" + stringin.to_s + ")"
    end
    return ""
  end


end
