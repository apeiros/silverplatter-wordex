= Summary
WordEx is a word based pattern matching library. It is similar to Regexp.
But while Regexp matches individual words, WordEx is built to match word sequences.



= Demo cases
=== With a variable word
`WordEx.new("I saw them playing :game yesterday").
     match("I saw them playing tennis yesterday")
# => {:game => "tennis"}`

=== With a variable substring
`WordEx.new("I saw them +doing yesterday").
     match("I saw them playing tennis yesterday")
# => {:doing=>"playing tennis"}`

=== Automatic conversion
`WordEx.new("I have :apple_count@Integer apples").
     match("I have 5 apples")
# => {:apple_count=>5}

=== Validation
`WordEx.new("I have :apple_count@Integer apples").
     match("I have many apples")
# => nil`

=== Enforce positive values
`WordEx.new("I have :apple_count@+Integer apples").
     match("I have -5 apples")
# => nil`
