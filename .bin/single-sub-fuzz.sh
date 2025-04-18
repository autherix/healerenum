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


single_sub_fuzz() {
    
    # Run httpx on the current subdomain to make sure it's up and running, and to build an asset out of the subdomain and save it to a var to be used later
    fuzz_db=$db
    fuzz_target=$target
    fuzz_domain=$1
    fuzz_subdomain=$2
    fuzz_wordlist="/lst/dir/test-200.txt"
    # fuzz_wordlist="/lst/dir/fixed_dirsearch.txt"    
    # c_asset=$(httpx -silent -no-color -no-fallback -no-status -no-title -no-websocket -threads 1 -timeout 10 -ports 80,443 -content-length -follow-redirects -l $2 | tee /dev/tty)
    
    # Run httpx on it and save it to a var to be used later
    c_asset=$(httpx -u $fuzz_subdomain -H "user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36" -H "Host: $fuzz_subdomain" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7" -mc 200 -no-color -silent) # -fr

    c_asset_not_bad=$(httpx -u $fuzz_subdomain -H "user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36" -H "Host: $fuzz_subdomain" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7" -no-color -silent) 

    # find the last url in the output
    c_asset=$(echo $c_asset | grep -Eo "(http|https)://[a-zA-Z0-9./?=_-]*" | tail -n 1)

    # If c_asset is empty, return
    if [[ -z "$c_asset" ]]; then
        # send a curl request to $ fuzz_subdomain, if the response header Content type is text/plain, set c_asset to $c_asset_not_bad, else return
        curl_out_content_type=$(curl -s -I $fuzz_subdomain -L | grep "content-type: " | awk '{print $2}')
        if [[ "$curl_out_content_type" == *"text/plain"* ]] || [[ "$curl_out_content_type" == *"text/xml"* ]] || [[ "$curl_out_content_type" == *"application/xml"* ]] || [[ "$curl_out_content_type" == *"application/json"* ]]; then
            c_asset=$c_asset_not_bad
        else
            printf "[-] No valid urls found for $2\n"
            printf "Report: $fuzz_subdomain\n" 
            return
        fi
    fi

    # If last char is not /, append it
    if [[ ! "$c_asset" =~ /$ ]]; then
        c_asset="$c_asset/"
    fi

    # Send a curl request to c_asset without fetching body, to get the status code and redirect url
    curl_out=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" $c_asset)
    curl_out_status_code=$(echo $curl_out | awk '{print $1}')
    curl_out_redirect_url=$(echo $curl_out | awk '{print $2}')
    # if status code is not 200 AND redirect url is not starting with c_asset AND redirect url is not empty, return
    if [[ "$curl_out_status_code" != "200" ]] && [[ ! "$curl_out_redirect_url" =~ ^"$c_asset" ]] && [[ -n "$curl_out_redirect_url" ]]; then
        printf "[-] $c_asset is not up or it's redirecting to a different subdomain\nCurrent Subdomain: $fuzz_subdomain\nRedirect URL: $curl_out_redirect_url\nCurrent Asset: $c_asset\n"
        return
    else
        printf "[+] Running ffuf on $c_asset\n"
    fi

    # Run ffuf on it
    ffuf -u "$c_asset"FUZZ -w $fuzz_wordlist -recursion -recursion-depth 1 -recursion-strategy "greedy" -json -o /tmp/ffuf_out_$fuzz_subdomain.json -H "User-Agent: Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" -H "Host: $fuzz_subdomain" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7" -mc 200 -timeout 10 -s  > /dev/null 2>&1 # -ac -r -s

    # # Wait until ffuf and its subprocesses finish
    # wait $(jobs -p) 

    # ffuf -u dashboard.hiltonmanage.com/FUZZ -w "/lst/dir/dirsearch.txt" -recursion -recursion-depth 1 -recursion-strategy "greedy" -r -json -mc 200 -o /tmp/ffuf_out_dashboard.hiltonmanage.com.json -H "User-Agent: Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" -s -mc 200 -ac -timeout 10


    # check if /tmp/ffuf_out_$fuzz_subdomain.json exists, if not, return
    if [[ ! -f "/tmp/ffuf_out_$fuzz_subdomain.json" ]]; then
        printf "[-] No directories found for $c_asset, ffuf output file does not exist\n"
        return
    fi

    # save output file to a var
    ffuf_out=$(cat /tmp/ffuf_out_$fuzz_subdomain.json)

    # If ffuf_out is empty, return
    if [[ -z "$ffuf_out" ]]; then
        printf "[-] No directories found for $c_asset, ffuf output is empty !\n"
        return
    fi

    # Remove the output file
    # rm /tmp/ffuf_out_$fuzz_subdomain.json

    # use jq and get the result part
    ffuf_out_results_urls="$(echo "$ffuf_out" | jq -r '.results[].url' | sort -u)"

    # If ffuf_out_results_urls is empty, return
    if [[ -z "$ffuf_out_results_urls" ]]; then
        printf "[-] No directories found for $c_asset\n"
        return
    fi

    # remove the c_asset from the start of each item in ffuf_out_results_urls
    ffuf_out_results_urls_with_c_asset=$ffuf_out_results_urls

    # Iterate over ffuf_out_results_urls_with_c_asset and if the url does not start with c_asset, add it before each url
    for url in $ffuf_out_results_urls_with_c_asset; do
        # If url does not start with c_asset
        if [[ ! "$url" =~ ^"$c_asset" ]]; then
            # If url is not starting with /, add it 
            if [[ ! "$url" =~ ^"/" ]]; then
                url="/$url"
            fi
            # Add c_asset to the start of url
            url="$c_asset$url"
        fi
    done

    # convert new lines to space
    ffuf_out_results_urls="$(echo $ffuf_out_results_urls | tr '\n' ' ')"

    # Save the results to the database using healerdb
    healerdb directory multi-create -db $fuzz_db -t $fuzz_target -d $fuzz_domain -sub $fuzz_subdomain -dir "$ffuf_out_results_urls" # > /dev/null 2>&1

    # also add complete urls to the database
    healerdb url multi-create -db $fuzz_db -t $fuzz_target -d $fuzz_domain -sub $fuzz_subdomain -u "$ffuf_out_results_urls_with_c_asset" # > /dev/null 2>&1
    # healerdb directory multi-create -db $fuzz_db -t $fuzz_target -d $fuzz_domain -sub $fuzz_subdomain -dir "$ffuf_out_new" > /dev/null 2>&1

    printf "[+] successfully saved directories for $2\n"

    ### FUZZing files ###

    # # Get the list of directories of this subdomain from the database using healerdb, remove 
    # fuzz_dirs=$(healerdb directory list -db $fuzz_db -t $fuzz_target -d $fuzz_domain -sub $fuzz_subdomain -j | jq -r '.result[]')

}

single_sub_fuzz $domain $subdomain