require "aws/s3"

module Amazon
    class S3
        unloadable # so you don't have to restart the server after changing a class in /lib
    
        def initialize(user=nil)
            @user = user
            @production_bucket = return_bucket("production")
            @target_buckets = [return_bucket("staging"), return_bucket("development")]  
        end
    
        def synchronize_photo(uploaded_file_path)          
            # remove the first "/" character - otherwise you can't get objects
            clean_uploaded_file_path = uploaded_file_path[1..-1] 
            
            prefix = ""
        
            # connect to production bucket
            AWS::S3::Base.establish_connection!( 
                :access_key_id => @production_bucket['access_key_id'],
                :secret_access_key => @production_bucket['secret_access_key']
            )
            
            if @user
                if @user.last_name # if the user has last name, include that in path
                    name = "#{@user.first_name.downcase.lstrip}-#{@user.last_name.downcase.lstrip}"
                    # e.g. prefix = /user/avatar/611/mark-muskardin 
                    prefix = clean_uploaded_file_path.match(/.*\d+\/#{name}/).to_s  
                elsif !@user.last_name # if not, don't include that in path
                    name = "#{@user.first_name.downcase.lstrip}"
                    # e.g. prefix = /user/avatar/611/mark
                    prefix = clean_uploaded_file_path.match(/.*\d+\/#{name}/).to_s
                end
            else
              # the prefix is for a blog image, e.g. prefix = /blog/images/110
              prefix = clean_uploaded_file_path.match(/.*\d+/).to_s
            end
            
            prod_objects = AWS::S3::Bucket.objects(@production_bucket['bucket'],:prefix => prefix)

            # iterate over all objects in directory and copy to target buckets
            prod_objects.each do |prod_obj|
                copy_from_production_to_targets(prod_obj)
            end
        end
    
        private
    
            # Return a connected Amazon S3 bucket
            def return_bucket(bucket_type) 
                bucket = YAML.load_file("#{::Rails.root.to_s}/config/s3.yml")[bucket_type]
            end
        
            # Synchronize the object with the buckets in the bucket array
            def copy_from_production_to_targets(obj)
                params = {}
                @target_buckets.each do |target_bucket|
                    AWS::S3::Base.establish_connection!( 
                        :access_key_id => target_bucket['access_key_id'],
                        :secret_access_key => target_bucket['secret_access_key']
                    )
                    # If object already exists
                    if target_bucket[obj.key]
                        # AWS::S3::S3Object.delete(obj.key,target_bucket['bucket'])
                        params.merge!('x-amz-copy-source-if-none-match' => target_bucket[obj.key].etag)
                    end
                    begin
                        AWS::S3::S3Object.store(obj.key, nil, target_bucket['bucket'], 
                          params.merge('x-amz-copy-source' => obj.path))
                        set_permissions(obj,target_bucket['bucket'])
                    rescue AWS::S3::ResponseError => error
                    end
                end
            end
        
            def set_permissions(obj,bucket_name)
                acl = AWS::S3::S3Object.acl(obj.key,bucket_name)
                acl.grants << AWS::S3::ACL::Grant.grant(:public_read)
                AWS::S3::S3Object.acl(obj.key,bucket_name,acl)    
            end
            
    end
end