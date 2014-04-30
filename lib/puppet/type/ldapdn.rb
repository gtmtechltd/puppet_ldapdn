Puppet::Type.newtype(:ldapdn) do

  ensurable do

    newvalue(:present) do
      provider.create
    end

    newvalue(:absent) do
      provider.destroy
    end

    defaultto :present

  end

  @doc = <<-EOS
    This type provides the capability to manage LDAP DN entries.
  EOS

  newparam(:name) do
    desc <<-EOS
      The canonical name of the rule.
    EOS
    isnamevar

    newvalues(/^.*$/)
  end

  newparam(:attributes, :array_matching => :all) do
    desc "Specify the attribute you want to ldapmodify"
  end

  newparam(:unique_attributes, :array_matching => :all) do
    desc "Specify the attribute that are unique in the dn"
  end

  newparam(:indifferent_attributes, :array_matching => :all) do
    desc "Specify the attributes you dont care about their subsequent values (e.g. passwords)"
  end

  newparam(:dn) do
    desc "Specify the value of the attribute you want to ldapmodify"
  end

end
