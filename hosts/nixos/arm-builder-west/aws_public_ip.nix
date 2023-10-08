{
  awscli,
  curl,
  gnused,

  secrets,
  pkgs,
  ...
}:
  pkgs.writeShellApplication {
    name = "aws_public_ip";
    runtimeInputs = [awscli curl gnused];
    text =  ''
      AWS_ACCESS_KEY_ID="$(sed 's/:.*//' < ${secrets.awscli-ip_builder-pw.plain})"
      export AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY="$(sed 's/.*://' < ${secrets.awscli-ip_builder-pw.plain})"
      export AWS_SECRET_ACCESS_KEY

      set -x

      CURL_OPTS="-vsSf"
      METADATA="http://169.254.169.254/latest/meta-data"

      INSTANCE="$(curl $CURL_OPTS $METADATA/instance-id)"
      REGION="$(curl $CURL_OPTS $METADATA/placement/region)"
      PUB_IP="$(curl $CURL_OPTS $METADATA/public-ipv4 || true)"

      callAws() {
        # echo 1>&2 \
        #     AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        #     AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
             aws --region="$REGION" --cli-connect-timeout=30 "$@" 
      }

      release() {
        callAws ec2 release-address --allocation-id="$1"
      }

      findAlloc() {
        callAws ec2 describe-addresses --public-ips "$1" \
          --query 'Addresses[0].AllocationId' | sed 's/"//g'
      }

      allocate() {
        echo 1>&2 "FAIL: Cannot allocate a public IP address without already having a"
        echo 1>&2 "public IP address (and thus internet connectivity) or some other"
        echo 1>&2 "means of reaching amazon services, such as a internet-gateway or"
        echo 1>&2 "service gateway".
        exit 1

        if [ -n "$PUB_IP" ]; then
          echo 1>&2 "Doing nothing; we already have a public IP address"
        else
          newAddress=""
          tries=1
          while [ -z "$newAddress" ] && [ "$tries" -lt 5 ]; do
            echo 1>&2 "Allocating new Elastic (public) IP address (try $tries)"
            newAddress="$(callAws ec2 allocate-address --domain=vpc --query 'PublicIp' | sed 's/\"//g')"
            tries=$((tries + 1))
          done

          if [ -n "$newAddress" ]; then
            echo 1>&2 "Associating address $newAddress with this instance $INSTANCE"
            
            callAws ec2 associate-address --no-allow-reassociation \
              --instance-id="$INSTANCE" --public-ip="$newAddress" || \
              if [ -n "$newAddress" ]; then
                echo 1>&2 "Failed to associate; releasing address $newAddress"
                alloc="$(findAlloc "$PUB_IP")"
                release "$alloc"
                exit 1
              fi

          else
            echo 1>&2 "Failed to allocate an IP address after multiple tries!"
            exit 1
          fi
        fi
      }

      deallocate() {
        if [ -z "$PUB_IP" ]; then 
          echo 1>&2 "Doing nothing; we already have no public IP address"
        else
          echo 1<&2 "Learning association id for address $PUB_IP"
          alloc="$(findAlloc "$PUB_IP")"
          echo 1>&2 "Disassociating address $PUB_IP from this instance $INSTANCE"
          callAws ec2 disassociate-address --public-ip="$PUB_IP"
          echo 1>&2 "Releasing Elastic (public) IP address $PUB_IP"
          release "$alloc"
        fi
      }

      case "''${1:-help}" in
        get)
          allocate
          ;;
        drop)
          deallocate
          ;;
        *)
          echo 1>&2 "Usage:"
          echo 1>&2 "$(basename "$0") get  # Attempt to get and associate a new public IP to this instance"
          echo 1>&2 "$(basename "$0") drop # Attempt to disassociate and release our existing public IP for this instance"
          exit 1
          ;;
      esac
    '';
  }
