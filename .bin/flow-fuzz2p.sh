#!/usr/bin/env bash

Usage() {
    printf "Usage: $0 [OPTIONS] [ARGS]\n"
    printf "Options:\n"
    printf "\t-h, --help\t\t\tShow this help message and exit\n"
    printf "\t-db, --database\t\t\tDatabase name to use, default is enum\n"
    printf "\t-t, --target\t\t\tTarget name to use, required\n"
    printf "\t-d, --domain\t\t\tDomain name to use, optional\n"
    printf "\t-sub, --subdomain\t\tSubdomain name to use, optional\n"
    printf "\t--args\t\t\t\tPass remaining args to single_sub_fuzz\n"
    printf "Args:\n"
    printf "\tARGS\t\t\t\tArguments to pass to single_sub_fuzz\n"
    printf "Examples:\n"
    printf "\t$0 -t target1\n"
    printf "\t$0 -t target1 -d domain1\n"
    printf "\t$0 -t target1 -d domain1 -sub subdomain1\n"
    printf "\t$0 -t target1 -d domain1 -sub subdomain1 --args -w /path/to/wordlist.txt -t 100\n"
    printf "\t$0 -t target1 -d domain1 -sub subdomain1 --args -w /path/to/wordlist.txt -t 100 -o /path/to/output.txt\n"
}

db=""
target=""
domain=""
subdomain=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            Usage
            exit 0
            ;;
        -db|--database)
            db="$2"
            shift
            shift
            ;;
        -t|--target)
            target="$2"
            shift
            shift
            ;;
        -d|--domain)
            domain="$2"
            shift
            shift
            ;;
        -sub|--subdomain)
            subdomain="$2"
            shift
            shift
            ;;
        --args)
            # Add remaining args to POSITIONAL until end of args or next flag(starting with -)
            while [[ $# -gt 0 ]]; do
                key="$1"
                if [[ $key == -* ]]; then
                    break
                fi
                POSITIONAL+=("$1")
                shift
            done
            break
            ;;
        *)
            echo "Unknown option: $key"
            Usage
            exit 1
            ;;
    esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters -what does this do? - it sets the positional parameters to the value of the array

if [[ -z "$db" ]]; then
    db="enum"
fi

if [[ -z "$target" ]]; then
    echo "Target not specified, Exiting"
    Usage
    exit 1
fi

# Get domain list fron healerdb
domains=$(healerdb domain list -db $db -t $target -j | jq -r '.result[]')

# If it's empty, exit with error
if [[ -z "$domains" ]]; then
    echo "No domains found for target $target, Exiting"
    exit 1
fi

# function single_sub_fuzz() to run single_sub_fuzz on a single subdomain
single_sub_fuzz() {
    
    # Run httpx on the current subdomain to make sure it's up and running, and to build an asset out of the subdomain and save it to a var to be used later
    fuzz_db=$db
    fuzz_target=$target
    fuzz_domain=$1
    fuzz_subdomain=$2
    fuzz_wordlist="/lst/dir/test-200.txt"    
    # c_asset=$(httpx -silent -no-color -no-fallback -no-status -no-title -no-websocket -threads 1 -timeout 10 -ports 80,443 -content-length -follow-redirects -l $2 | tee /dev/tty)
    
    # Run httpx on it and save it to a var to be used later
    c_asset=$(httpx -u $2 -mc 200 -fr -no-color -silent)

    # find the last url in the output, remove last ] 
    c_asset=$(echo $c_asset | grep -oP '(?<=\[).*(?=\])' | sed 's/.$//')

    # Remove last / if it exists
    if [[ "${c_asset: -1}" == "/" ]]; then
        c_asset="${c_asset::-1}"
    fi

    # If c_asset is empty, return
    if [[ -z "$c_asset" ]]; then
        printf "[-] No valid urls found for $2\n"
        return
    fi

    # Run ffuf on it
    ffuf -u $c_asset/FUZZ -w $fuzz_wordlist -recursion -recursion-depth 1 -recursion-strategy "greedy" -r -json -mc 200 -o /tmp/ffuf_out_$2.json -H "User-Agent: Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" -s -mc 200 -ac -timeout 10 > /dev/null 2>&1

    # save output file to a var
    ffuf_out=$(cat /tmp/ffuf_out_$2.json)

    # use jq and get the result part
    ffuf_out_results_urls=$(echo $ffuf_out | jq -r '.results[].url' | sort -u)

    # If ffuf_out_results_urls is empty, return
    if [[ -z "$ffuf_out_results_urls" ]]; then
        printf "[-] No directories found for $2\n"
        return
    fi

    # remove the c_asset from the start of each item in ffuf_out_results_urls
    ffuf_out_results_urls=$(echo $ffuf_out_results_urls | sed "s|$c_asset||g")

    # If ffuf_out_results_urls is empty, return
    if [[ -z "$ffuf_out_results_urls" ]]; then
        printf "[-] No directories found for $2\n"
        return
    fi

    # convert new lines to space
    ffuf_out_results_urls=$(echo $ffuf_out_results_urls | tr '\n' ' ')

    # Save the results to the database using healerdb
    healerdb directory multi-create -db $fuzz_db -t $fuzz_target -d $fuzz_domain -sub $fuzz_subdomain -dir "$ffuf_out_results_urls" > /dev/null 2>&1
    # healerdb directory multi-create -db $fuzz_db -t $fuzz_target -d $fuzz_domain -sub $fuzz_subdomain -dir "$ffuf_out_new" > /dev/null 2>&1

    printf "[+] successfully saved directories for $2\n"

    ### FUZZing files ###

    # # Get the list of directories of this subdomain from the database using healerdb, remove 
    # fuzz_dirs=$(healerdb directory list -db $fuzz_db -t $fuzz_target -d $fuzz_domain -sub $fuzz_subdomain -j | jq -r '.result[]')

}

# If domain is specified, check if it's not in the list, exit with error
if [[ -n "$domain" ]]; then
    if [[ ! "$domains" =~ "$domain" ]]; then
        echo "Domain $domain not found for target $target, Exiting"
        exit 1
    else 
        subdomains=$(healerdb subdomain list -db $db -t $target -d $domain -j | jq -r '.result[]')
        # If subdomain is specified, check if it's not in the list, exit with error
        if [[ -n "$subdomain" ]]; then
            if [[ ! "$subdomains" =~ "$subdomain" ]]; then
                echo "Subdomain $subdomain not found for target $target, domain $domain, Exiting"
                exit 1
            else
                # Run single_sub_fuzz() on it and saveit to a var to be used later
                single_sub_fuzz_result=$(single_sub_fuzz $domain $subdomain)
                printf "$single_sub_fuzz_result\n"
            fi
        else
            # Iterate over subdomains
            for subdomain in $subdomains; do
                # Run single_sub_fuzz() on it and saveit to a var to be used later
                single_sub_fuzz_result=$(single_sub_fuzz $domain $subdomain)
                printf "$single_sub_fuzz_result\n"
            done
        fi
    fi
else
    # Iterate over domains
    for domain in $domains; do
        # Get subdomains for each domain
        subdomains=$(healerdb subdomain list -db $db -t $target -d $domain -j | jq -r '.result[]')
        # Iterate over subdomains
        for subdomain in $subdomains; do
            # Run single_sub_fuzz() on it and saveit to a var to be used later
            single_sub_fuzz_result=$(single_sub_fuzz $domain $subdomain)
            printf "$single_sub_fuzz_result\n"
        done
    done
fi
