#!/usr/bin/env bash

Usage() {
    printf "Usage Here"
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
    printf "Running single_sub_fuzz on $1\n"
}


# If domain is specified, check if it's not in the list, exit with error
if [[ -n "$domain" ]]; then
    if [[ ! "$domains" =~ "$domain" ]]; then
        echo "Domain $domain not found for target $target, Exiting"
        exit 1
    else 
        subdomains=$(healer///db subdomain list -db $db -t $target -d $domain -j | jq -r '.result[]')
        # If subdomain is specified, check if it's not in the list, exit with error
        if [[ -n "$subdomain" ]]; then
            if [[ ! "$subdomains" =~ "$subdomain" ]]; then
                echo "Subdomain $subdomain not found for target $target, domain $domain, Exiting"
                exit 1
            else
                # Run single_sub_fuzz() on it and saveit to a var to be used later
                single_sub_fuzz_result=$(single_sub_fuzz $subdomain)
                printf "$single_sub_fuzz_result\n"
            fi
        else
            # Iterate over subdomains
            for subdomain in $subdomains; do
                # Run single_sub_fuzz() on it and saveit to a var to be used later
                single_sub_fuzz_result=$(single_sub_fuzz $subdomain)
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
            single_sub_fuzz_result=$(single_sub_fuzz $subdomain)
            printf "$single_sub_fuzz_result\n"
        done
    done
fi
