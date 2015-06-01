package Kyloe::DBTools::FormBuidlder;

use CGI::FormBuilder;

# Generate/ process a form (wrapper for CGIFormBuilder)

# Generate/ process a Parent/Child form (wrapper for CGIFormBuilder)
# Specify number of rows

sub new
{
	my $class    = shift;    # Determine the class for the oject to create ok

	my $obj = {};                       # Instantiate a generic empty object

	bless $obj, $class; # 'bless' this new generic object into the desired class

 	return $obj;    # Return our newly blessed and loaded object
}


sub buildForm {
	my $self = shift;
	my 
}
