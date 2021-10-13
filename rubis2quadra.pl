#!/usr/bin/perl

use Data::Dumper;

use constant BUILD_CVS => 0 ;
use constant BUILD_TXT => 1 ;

my $file ;
if ($ARGV[0]) {
	$file = $ARGV[0];
} else {
	warn "Aucun fichier specifier, je prend le fichier le plus recent\n" ;
}

if (!$file) { # si aucun nom n'a été donné pour la tranformation, on essai de voir le fichier le plus recent dans le répertoire
	my @files = ();
	opendir(DIR,".") or die "Ne peux pas ouvrir le repertoire ($!)";
	while($_ = readdir(DIR)) {
		if(/^(\d{4}\-\d{2}\-rubis\.txt)$/i) { # si le nom du fichier correspond a yyyy-mm-rubis.txt --> on le garde
			push @files,$_ ;
		}
	}
	closedir(DIR);
	$file = (reverse sort (@files))[0];
}

print "Converstion du fichier '$file'\n";

open(F,"<$file") or die "Ne peux pas ouvrir le journal '$file' ($!)";

my ($filename_without_ext) = ($file =~ m/(.+)\.txt$/i);
if (BUILD_TXT) {
	open(FOUT,"+>${filename_without_ext}-quadra.txt") or die "Ne peux pas creer le fichier quadra '$filename_without_ext.txt' ($!)"; 
}
if (BUILD_CVS) {
	open(FCSV,"+>${filename_without_ext}.csv") or die "Ne peux pas creer le fichier quadra '$filename_without_ext.csv' ($!)";
}


# ecrit le header du csv
print FCSV join(';',qw/numero date reference echeance numero_compte libelle_compte libelle_ecriture sens montant debit credit/)."\n" if BUILD_CVS;

my $journal_en_cours = '' ;
my ($ligne,$ligne_traitee)=(0,0);
while(<F>) {
	chomp;
	
	# on regarde le journal en cours
	if (/^Soc\.\s+:\s+MCS\s+Journal\s+:\s+(\S+)/) {
		my $old_journal = $journal_en_cours ;
		$journal_en_cours = substr($1,0,3); # code journal sur 3 car
		print "NOUVEAU journal : '$journal_en_cours'\n" if $old_journal ne $journal_en_cours;
	}

	# ancien format
	#!S    18719  7/01/08 ! FAFA    711888           ! 29.02.08 ! 411056001  ALRE CHAUFFAGE SANITAIRE            ALRE CHAUFFAGE SANITAIRE           !        272,04                !

	# nouveau format
	#!S        1 15/04/16!AAFA     30878                !31.05.16 !411056039  CAB 56                              CAB 56                             !                        94,43 !

	# on regarde si la ligne correspond a une ligne d'écriture comptable
	if (my ($numero,$date_jour,$date_mois,$date_annee,$facture_ou_avoir,$reference,$date_echeance,$numero_compte,$libelle_compte,$libelle_ligne,$debit,$credit) = 
		(/	^!S\s+				# ligne d'écriture
			(\d+)				# numéro
			\s+
			(\d+)\/(\d+)\/(\d+)	# date
			\s*!\s*
			([\w\d]+)			# FAFA ou AAFA -> avoir ou facture
			\s+
			([^!]+)				# référence
			!
			([^!]+)				# Date Echéance -> non obligatoire
			!\s*
			([\w\d\-\.]+)		# n° de compte
			\s+
			(.{36})				# libéllé du compte
			([^!]+)				# libéllé écriture
			!
			(.{14})				# débit
			(.{15})				# crédit
		/xi)) {

			die "ERREUR : Aucun journal de specifie\n" unless $journal_en_cours ;

			# extraction du code client
			my $code_client = substr($numero_compte,length($numero_compte)-6,6);

			# formatage des données
			$debit			= trim($debit);		my $debit_centime  = $debit ;	$debit_centime =~ s/,//g; # montant en centime
			$credit			= trim($credit);	my $credit_centime = $credit ;	$credit_centime =~ s/,//g; # montant en centime
			$libelle_compte = trim($libelle_compte);
			$numero_compte =~ s/^411/01/;
			$numero_compte =~ s/^401/08/;
			$numero_compte =~ s/^457256/4572/;
			$numero_compte =~ s/^457856/4578/;
			if (length($numero_compte) > 8) { # numero_compte trop long --> 8 car max !				
				$numero_compte = substr($numero_compte,0,8);
			}
			$numero_compte	= $numero_compte.(' ' x (8 - length($numero_compte)));
			$date_jour		= sprintf('%02d',$date_jour) ;
			$date_mois		= sprintf('%02d',$date_mois) ;
			$date_annee		= sprintf('%02d',$date_annee) ;
			$libelle_ligne	= substr($libelle_ligne,0,20); # libelle_ligne trop long --> 20 car max !
			$reference = substr(trim($reference),0,8);
			$reference =~ s/\s+.*$//;

			my ($sens,$montant,$montant_centime) ;
			if ($debit) {
				$sens		= 'D';
				$montant_centime		= '+'.('0' x (12 - length($debit_centime))).$debit_centime ;
				$montant = $debit;
			} else {
				$sens		= 'C';
				$montant_centime		= '+'.('0' x (12 - length($credit_centime))).$credit_centime ;
				$montant = $credit;
			}

			if ($date_echeance =~ /(\d+)\.(\d+)\.(\d+)/) {
				$date_echeance = sprintf('%02d',$1).sprintf('%02d',$2).sprintf('%02d',$3);
			} else {
				$date_echeance = '0' x 6 ;
			}
			
			$code_journal = $journal_en_cours ;
			$code_journal =~ s/VTE/VE/i;

			print FOUT	'M'.									# Type = M sur 1 car
						$numero_compte.							# Numero du compte sur 8 cara
						'VE'.									# Code journal 'VE' sur 2 car
						'000'.									# numero du folio sur 3 car
						$date_jour.$date_mois.$date_annee.		# date écriture sur 6 car
						'F'.									# code libellé sur 1 car
						$libelle_ligne.							# libelle ligne sur 20 car
						$sens.									# sens D ou C sur 1 car
						$montant_centime.						# montant signé 13 car
						(' ' x 8).								# compte de contre partie sur 8 car
						$date_echeance.							# date d'écheance sur 6 car
						(' ' x 2).								# code lettrage sur 2 car
						(' ' x 3).								# code stat sur 3 car
						(' ' x 5).								# code piece sur 5 car
						(' ' x 10).								# code affaire sur 10 car
						(' ' x 10).								# quantite sur 10 car
						$reference.(' ' x (8 - length($reference))).	# code piece sur 8 car
						'EUR'.									# devis sur 3 car
						$code_journal.(' ' x (3 - length($code_journal))).	# code journal sur 3 car
						' '.									# flag code TVA sur 1 car
						' '.									# code TVA sur 1 car
						' '.									# methode de calcul TVA sur 1 car
						(' ' x 115).							# rempli de blanc pour le system d'import
						"\n" if BUILD_TXT;

				# si une date d'échéance est présente, on renseigne le type de reglement
				if ($date_echeance ne '000000' && BUILD_TXT) {
					print FOUT	'R'.							# Type = R sur 1 car
								$date_echeance.					# date d'échéance sur 6 car
								$montant_centime.				# montant signé 13 car
								(' ' x 2).						# code reglement sur 2 car (vide car utilisé sur 4 car plus bas)
								(' ' x 2).						# code journal de banque
								(' ' x 10).						# référence tiré
								(' ' x 23).						# RIB tiré
								(' ' x 20).						# Domiciliation banquaire
								(' ' x 3).						# Code journal de banque
								(' ' x 8).						# n° de compte d'origine
								#$code_reglement_clients{$code_client}.	# code reglement sur 4 car
								'PRL '.	# code reglement sur 4 car
								(' ' x 1).						# Bon à payer
								"\n";
				}


				#numero date reference echeance numero_compte libelle_compte libelle_ecriture sens montant debit credit
				print FCSV join(';',
								(
									$numero,
									$date_jour.$date_mois.$date_annee,
									$facture_ou_avoir.' '.$reference,
									$date_echeance,
									trim($numero_compte),
									trim($libelle_compte),
									trim($libelle_ligne),
									$sens,
									$montant,
									$debit,
									$credit
								)
							)."\n" if BUILD_CSV;

		$ligne++;

	} else { # ce n'est pas une écriture comptable
		print "REJETE '$_'\n" if (/^!S/); # aurait du être traité
		next ;
	}

} #fin while lignedu fichier

close F;
close FOUT if BUILD_TXT;
close FCSV if BUILD_CSV;

print  "Nombre de ligne du fichier : $ligne\n";

sub trim {
	my $arg = shift;
	$arg =~ s/^\s+|\s+$//g;
	return $arg ;
}