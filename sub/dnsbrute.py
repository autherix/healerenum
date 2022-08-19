import os
import time
import datetime
import subprocess
import os
import sys
import argparse


parser = argparse.ArgumentParser(description="DNSBrute: Gathering Subdomains Using Multiple Sources.")

parser.add_argument("-d", "--domain",
    help="Enter your target domain name.", default=False)
parser.add_argument("-w", "--wordlist",
    help="Enter your DNS wordlist.", default=False)
parser.add_argument("-r", "--resolvers",
    help="Enter your resolvers filename.", default="resolvers.txt")
parser.add_argument("-f", "--fast",
    help="Do you want to create shorter wordlist from DNSGen (y/n)? [Default: y]", default=True)
parser.add_argument("-v", "--verbose", action="store_true",
    help="Show More Verbose Debug Messages.", default=True)

options = parser.parse_args()

def debug_print(message):
    if options.verbose:
        print(message)

if not options.domain:
    print("Please Enter Your Target Domain Name.")
    sys.exit(0)

if not options.wordlist:
    print("Please Enter DNS Wordlist File Name.")
    sys.exit(0)

if "n" in str(options.fast):
    SHORT_DNSGEN = False
else:
    SHORT_DNSGEN = True

print(f"[!] Using '{options.resolvers}' As Resolver File.")

if SHORT_DNSGEN:
    print("[!] Using -f switch in DNSGen.")

DNS_WORDLIST_NAME = options.wordlist
DOMAIN_NAME = options.domain
RESOLVER_FILENAME = options.resolvers
used_filenames = []

def get_current_time(type="filename"):
    current_time = str(datetime.datetime.now())
    current_time = current_time[:19]
    if type == "filename":
        current_time = current_time.replace(":", "-")
        current_time = current_time.replace(" ", "_")
    return current_time

def delete_file(filename):
    try:
        os.remove(filename)
    except:
        pass

def generate_dns_wordlist(domain):
    global used_filenames
    print(f"[+] Generating subdomains based on your DNS wordlist [{get_current_time('time')}]")
    base_wordlist_handle = open(DNS_WORDLIST_NAME, "r", encoding="utf-8", errors="ignore").readlines()
    base_wordlist_handle = [word.strip() for word in base_wordlist_handle]
    final_wordlist = []
    for word in base_wordlist_handle:
        final_wordlist.append(f"{word}.{domain}")
    filename = f"{domain}_dns_wordlist.txt"
    used_filenames.append(filename)
    final_wordlist_handle = open(filename, "w", encoding="utf-8", errors="ignore")
    for word in final_wordlist:
        final_wordlist_handle.write(f"{word}\n")
    final_wordlist_handle.close()

def get_subfinder_subdomains(domain):
    print(f"[+] Fetching subdomains using 'SubFinder' [{get_current_time('time')}]")
    global used_filenames
    subfinder_output_filename = f"{domain}_subfinder.txt"
    used_filenames.append(subfinder_output_filename)
    command = f"subfinder -d {domain} -nC -silent > {subfinder_output_filename}"
    debug_print(f"[DBUG] Command: {command}")
    output = subprocess.call(command, shell=True)

def get_crtsh_subdomains(domain):
    print(f"[+] Fetching subdomains using 'crt.sh' [{get_current_time('time')}]")
    global used_filenames
    crtsh_output_filename = f"{domain}_crtsh.txt"
    used_filenames.append(crtsh_output_filename)
    command = f"curl -sk \"https://crt.sh/?q={domain}&output=json\" | jq -r '.[].common_name,.[].name_value' | sed 's/*.//g' | sort -u > {crtsh_output_filename}"
    debug_print(f"[DBUG] Command: {command}")
    output = subprocess.call(command, shell=True, stdout=subprocess.PIPE)

def get_abuseipdb_subdomains(domain):
    print(f"[+] Fetching subdomains using 'AbuseIP DB' [{get_current_time('time')}]")
    global used_filenames
    abuseipdb_output_filename = f"{domain}_abuseipdb.txt"
    used_filenames.append(abuseipdb_output_filename)
    command = f"curl -s \"https://www.abuseipdb.com/whois/{domain}\" -H \"user-agent: Chrome\" | grep -E '<li>\w.*</li>' | sed -E 's/<\/?li>//g' | sed -e \"s/$/.{domain}/\" | sort -u > {abuseipdb_output_filename}"
    debug_print(f"[DBUG] Command: {command}")
    output = subprocess.call(command, shell=True)

def unique_files(input_filename, output_filename):
    for file in input_filename:
        os.chmod(file, 0o777)

    filenames = " ".join(input_filename)
    command = f"cat {filenames} | sort -u > {output_filename}"
    debug_print(f"[DBUG] Message: Merging Files Together.")
    debug_print(f"[DBUG] Command: {command}")
    output = subprocess.call(command, shell=True)
    os.chmod(output_filename, 0o777)

def resolve_shuffledns(subdomains_filename, outputname):
    print(f"[+] Resolving subdomains in '{subdomains_filename}' [{get_current_time('time')}]")
    # command = f"massdns -q -r resolvers.txt -t A -o L -w {outputname} {subdomains_filename}"
    # command = f"shuffledns -d {DOMAIN_NAME} -list {subdomains_filename} -r {RESOLVER_FILENAME} -silent > {outputname}"
    command = f"puredns resolve {subdomains_filename} --resolvers {RESOLVER_FILENAME} -q > {outputname}"
    debug_print(f"[DBUG] Command: {command}")
    output = subprocess.call(command, shell=True)
    os.chmod(outputname, 0o777)

def dnsgen_wordlist(input_filename, outputfilename):
    print(f"[+] Creating subdomain wordlist using dnsgen. [{get_current_time('time')}]")
    if SHORT_DNSGEN:
        command = f"cat {input_filename} | dnsgen -f - | sort -u > {outputfilename}"
    else:
        command = f"cat {input_filename} | dnsgen - | sort -u > {outputfilename}"
    debug_print(f"[DBUG] Command: {command}")
    output = subprocess.call(command, shell=True)
    os.chmod(outputfilename, 0o777)


get_subfinder_subdomains(DOMAIN_NAME)
get_crtsh_subdomains(DOMAIN_NAME)
get_abuseipdb_subdomains(DOMAIN_NAME)

# Merging all providers subdomains into a single unique file
filenames = [f"{DOMAIN_NAME}_abuseipdb.txt", f"{DOMAIN_NAME}_crtsh.txt", f"{DOMAIN_NAME}_subfinder.txt"]
unique_provider_output_name = f"{DOMAIN_NAME}_unique_provider_subdomains.txt"
used_filenames.append(unique_provider_output_name)
unique_files(filenames, unique_provider_output_name)

# Creating a wordlist containing domain.tld.{word}
domain_dns_wordlist_filename = f"{DOMAIN_NAME}_dns_wordlist.txt"
generate_dns_wordlist(DOMAIN_NAME)

# Combining "unique subdomains" + "Wordlist Sub-Domains"
unique_output_name = f"{DOMAIN_NAME}_unique_subdomains.txt"
used_filenames.append(unique_output_name)
filenames = [unique_provider_output_name, domain_dns_wordlist_filename]
unique_files(filenames, unique_output_name)

shuffledns_outputname = f"{DOMAIN_NAME}_resolved_subdomains.txt"
used_filenames.append(shuffledns_outputname)
resolve_shuffledns(f"{DOMAIN_NAME}_unique_subdomains.txt", shuffledns_outputname)

dnsgen_input_filename = f"{DOMAIN_NAME}_dnsgen_input_wordlist.txt"
used_filenames.append(dnsgen_input_filename)
filenames = [shuffledns_outputname, unique_provider_output_name]
unique_files(filenames, dnsgen_input_filename)

dnsgen_output_filename = f"{DOMAIN_NAME}_dnsgen_output.txt"
used_filenames.append(dnsgen_output_filename)
dnsgen_wordlist(dnsgen_input_filename, dnsgen_output_filename)

dnsgen_resolved_filename = f"{DOMAIN_NAME}_dnsgen_resolved_domains.txt"
used_filenames.append(dnsgen_resolved_filename)
resolve_shuffledns(dnsgen_output_filename, dnsgen_resolved_filename)

filenames = [dnsgen_resolved_filename, shuffledns_outputname]
final_domains_outputname = f"final_{DOMAIN_NAME}_subdoamins_{get_current_time()}.txt"
unique_files(filenames, final_domains_outputname)

for file in used_filenames:
    try:
        os.chmod(file, 0o777)
        delete_file(file)
    except Exception as e:
        print(f"[-] Failed To Remove [{file}]\n\t[Err] {e}")
