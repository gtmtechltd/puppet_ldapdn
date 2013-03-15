puppet_ldapn
============

puppet_ldapdn is a puppet type and provider that aims to simply manage newer slapd.d style openldap entries via ldapmodify and ldapadd commands. This is much more preferable than writing files directly to the slapd.d database.

In essence the mechanism it uses is described as follows:

* Translate the puppet "ldapdn" resource into an in-memory ldif
* ldapsearch the existing dn to verify the current contents (if any)
* compare the results of the search with what should be the case
* work out which add/modify/delete commands are required to get to the desired state
* write out an appropriate ldif file
* execute it via an ldapmodify statement.

This puppet resource is currently in it's infancy and is capable of running successfully. However, it may need extending for your particular case as follows:

* It uses the -Y EXTERNAL -H ldapi:/// SASL authentication mechanism. You may wish to bind specifically using an authorised dn, however this is on the todo list (or alternatively feel free to fork and submit)

Examples of usage are as follows:

First you might like to set a root password:

```puppet
ldapdn{"add manager password":
  dn => "olcDatabase={2}bdb,cn=config",
  attributes => "olcRootPW: password",
  unique_attributes => ["olcRootPW"],
  ensure => present,
}
```

attributes sets the attributes that you wish to set (be sure to separate key and value with <semi-colon space>).
unique_attributes can be used to specify the behaviour of ldapmodify when there is an existing attribute with this name. If the attribute key is specified here, then the ldapmodify will issue a replace, replacing the existing value (if any), whereas if the attribute key is not specified here, then ldapmodify will simply ensure the attribute exists with the value required, alongside other values if also specified (e.g. for objectClass).

```puppet
$organizational_units = ["Groups", "People", "Programs"]
ldap::add_organizational_unit{ $organizational_units }

define ldap::add_organizational_unit () {

ldapdn{ "ou ${name}":
  dn => "ou=${name},dc=example,dc=com",
  attributes => [ "ou: ${name}",
                  "objectClass: organizationalUnit" ],
  unique_attributes => ["ou"],
  ensure => present,
}
```

In the above example, multiple groups are created. Notice in each case, that "objectClass" does not form part of the unique_attributes, so that (in future) more objectClasses may be added to each ou, without them being replaced.

Here is how you can create a database in the first place:

```puppet

ldapdn{"set general access":
  dn => "olcDatabase={2}bdb,cn=config",
  attributes => ["olcAccess: {1}to * by self write by anonymous auth by dn.base="cn=Manager,dc=example,dc=com" write by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage by * read"],
  ensure => present
} ->

ldapdn{"add database":
  dn => "dc=example,dc=com",
  attributes => ["dc: example",
                 "objectClass: top",
                 "objectClass: dcObject",
                 "objectClass: organization",
                 "o: example.com"],
  unique_attributes => ["dc", "o"],
  ensure => present
}
```

As mentioned, all ldap commands are issued with -Y EXTERNAL SASL auth mechanism. For this reason, the "set general access" ldapdn above allows managing of the bdb database to this external mechanism, which then allows you to create the database without a "no write access to parent" error.

Sometimes you will want to ensure an attribute exists, but wont care about its subsequent value. An example of this is a password.

```puppet
ldapdn{"add password":
  dn => "cn=Geoff,ou=Staff,dc=example,dc=com",
  attributes => ["olcUserPassword: {SSHA}somehash..."],
  unique_attributes => ["olcUserPassword"],
  indifferent_attributes => ["olcUserPassword"],
  ensure => present
}
```

By specifying indifferent_attributes, ensure => present will ensure that if the key doesn't exist, it will create it with the desired passwordhash, but if the key does exist, it won't bother replacing it again. In this way you can keep passwords managed by something like phpldapadmin if you so wish.

Please report any bugs, and enjoy.

License
=======

This software is copyright free. Enjoy


