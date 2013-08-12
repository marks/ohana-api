require 'spec_helper'

describe Api::V1::OrganizationsController do

  describe "CORS REQUESTS" do
    context "when ORIGIN is specified" do
      before :each do
        organization = create(:organization)
        get 'api/organizations', {},
          { 'Accept' => 'application/vnd.ohanapi+json; version=1',
            'HTTP_ORIGIN' => 'http://ohanapi.org', 'HTTP_USER_AGENT' => "Rspec" }
      end

      it "gets version 1" do
        response.status.should == 200
      end

      it "retrieves a content-type of json" do
        headers['Content-Type'].should include 'application/json'
      end

      it "includes CORS headers when ORIGIN is specified" do
        headers.keys.should include("Access-Control-Allow-Origin")
        headers['Access-Control-Allow-Origin'].should == 'http://ohanapi.org'
      end

      it "allows GET, POST, & PUT HTTP methods thru CORS" do
        allowed_http_methods = headers['Access-Control-Allow-Methods']
        %w{GET POST PUT}.each do |method|
          allowed_http_methods.should include(method)
        end
      end
    end

    context "when ORIGIN is not specified" do
      it "does not include CORS headers when ORIGIN is not specified" do
        get 'api/organizations', {}, { 'HTTP_USER_AGENT' => "Rspec" }
        headers.keys.should_not include("Access-Control-Allow-Origin")
        headers['Access-Control-Allow-Origin'].should be_nil
      end
    end
  end

  describe "Link Headers" do
    before (:each) do
      31.times { organization = create(:organization) }
    end

    context "when on page 1 of 2" do
      it "returns a Link header" do
        get 'api/organizations', {}, { 'HTTP_USER_AGENT' => "Rspec" }
        headers["Link"].should ==
        '<http://www.example.com/api/organizations?page=2>; '+
        'rel="last", '+
        '<http://www.example.com/api/organizations?page=2>; '+
        'rel="next"'
      end
    end

    context "when on page 2 of 2" do
      it "returns a Link header" do
        get 'api/organizations?page=2', {}, { 'HTTP_USER_AGENT' => "Rspec" }
        headers["Link"].should ==
        '<http://www.example.com/api/organizations?page=1>; '+
        'rel="first", '+
        '<http://www.example.com/api/organizations?page=1>; '+
        'rel="prev"'
      end
    end

    context "when on page 2 of 3" do
      it "returns a Link header" do
        31.times { organization = create(:organization) }
        get 'api/organizations?page=2', {}, { 'HTTP_USER_AGENT' => "Rspec" }
        headers["Link"].should ==
        '<http://www.example.com/api/organizations?page=1>; '+
        'rel="first", '+
        '<http://www.example.com/api/organizations?page=1>; '+
        'rel="prev", '+
        '<http://www.example.com/api/organizations?page=3>; '+
        'rel="last", '+
        '<http://www.example.com/api/organizations?page=3>; '+
        'rel="next"'
      end
    end

    context "when there are more than 30 nearby locations" do
      it "returns a Link header" do
        nearby = create(:nearby_org)
        get "api/organizations/#{nearby.id}/nearby", {}, { 'HTTP_USER_AGENT' => "Rspec" }
        headers["Link"].should ==
        "<http://www.example.com/api/organizations/#{nearby.id}/nearby?page=2>; "+
        "rel=\"last\", "+
        "<http://www.example.com/api/organizations/#{nearby.id}/nearby?page=2>; "+
        "rel=\"next\""
      end
    end
  end

  describe "No API token in request" do
    context "when the rate limit has not been reached" do
      before { get 'api/organizations', {}, { 'HTTP_USER_AGENT' => "Rspec" } }

      it 'returns the requests limit headers' do
        headers['X-RateLimit-Limit'].should == "60"
      end

      it 'returns the remaining requests header' do
        headers['X-RateLimit-Remaining'].should == "59"
      end
    end

    context "when the rate limit has been reached" do

      before :each do
        key = "ohanapi_defender:127.0.0.1:#{Time.now.strftime('%Y-%m-%dT%H')}"
        REDIS.set(key, "60")
        get 'api/organizations', {}, { 'HTTP_USER_AGENT' => "Rspec" }
      end

      it_behaves_like "rate limit reached"
    end

    context "when User-Agent is blank" do
      before (:each) do
        get 'api/organizations'
      end

      it 'returns a 403 status' do
        response.status.should == 403
      end

      it 'returns a missing user agent message' do
        parsed_body = JSON.parse(response.body)
        parsed_body["description"].should == 'Missing or invalid User Agent string.'
      end
    end

    describe "when the 'If-None-Match' header is passed in the request" do
      context 'when the ETag has not changed' do

        before :each do
          get 'api/organizations', {}, { 'HTTP_USER_AGENT' => "Rspec" }
          etag = headers['ETag']
          get 'api/organizations', {}, { 'HTTP_IF_NONE_MATCH' => etag, 'HTTP_USER_AGENT' => "Rspec" }
        end

        it 'returns a 304 status' do
          response.status.should == 304
        end

        it 'returns the requests limit headers' do
          headers['X-RateLimit-Limit'].should == "60"
        end

        it 'does not decrease the remaining requests' do
          headers['X-RateLimit-Remaining'].should == "59"
        end
      end

      context 'when the ETag has changed' do

        before :each do
          get 'api/organizations', {}, { 'HTTP_USER_AGENT' => "Rspec" }
          get 'api/organizations', {}, { 'HTTP_IF_NONE_MATCH' => "1234567890", 'HTTP_USER_AGENT' => "Rspec" }
        end

        it 'returns a 200 status' do
          response.status.should == 200
        end

        it 'returns the requests limit headers' do
          headers['X-RateLimit-Limit'].should == "60"
        end

        it 'decreases the remaining requests' do
          headers['X-RateLimit-Remaining'].should == "58"
        end
      end
    end
  end

  describe "API token in request" do
    let(:valid_attributes) { { name: "test app",
                             main_url: "http://localhost:8080",
                             callback_url: "http://localhost:8080" } }

    before (:each) do
      user = FactoryGirl.create(:user)
      api_application = user.api_applications.create! valid_attributes
      @token = api_application.api_token
    end
    context "when the rate limit has not been reached" do
      before { get 'api/organizations', {}, { 'HTTP_X_API_TOKEN' => @token, 'HTTP_USER_AGENT' => "Rspec" } }

      it 'returns the requests limit headers' do
        headers['X-RateLimit-Limit'].should == "5000"
      end

      it 'returns the remaining requests header' do
        headers['X-RateLimit-Remaining'].should == "4999"
      end
    end

    context "when the rate limit has been reached" do

      before :each do
        key = "ohanapi_defender:127.0.0.1:#{Time.now.strftime('%Y-%m-%dT%H')}"
        REDIS.set(key, "5000")
        get 'api/organizations', {}, { 'HTTP_X_API_TOKEN' => @token, 'HTTP_USER_AGENT' => "Rspec" }
      end

      it_behaves_like "rate limit reached"
    end

    context "when User-Agent is blank" do
      before (:each) do
        get 'api/organizations', {}, { 'HTTP_X_API_TOKEN' => @token }
      end

      it 'returns a 403 status' do
        response.status.should == 403
      end

      it 'returns a missing user agent message' do
        parsed_body = JSON.parse(response.body)
        parsed_body["description"].should == 'Missing or invalid User Agent string.'
      end
    end

    describe "when the 'If-None-Match' header is passed in the request" do
      context 'when the ETag has not changed' do

        before :each do
          get 'api/organizations', {}, { 'HTTP_USER_AGENT' => "Rspec" }
          etag = headers['ETag']
          get 'api/organizations', {},
            { 'HTTP_IF_NONE_MATCH' => etag, 'HTTP_X_API_TOKEN' => @token, 'HTTP_USER_AGENT' => "Rspec" }
        end

        it 'returns a 304 status' do
          response.status.should == 304
        end

        it 'returns the requests limit headers' do
          headers['X-RateLimit-Limit'].should == "5000"
        end

        it 'does not decrease the remaining requests' do
          headers['X-RateLimit-Remaining'].should == "4999"
        end
      end

      context 'when the ETag has changed' do

        before :each do
          organization = create(:organization)
          get 'api/organizations', {}, { 'HTTP_USER_AGENT' => "Rspec" }
          get 'api/organizations', {},
            { 'HTTP_IF_NONE_MATCH' => "1234567890", 'HTTP_X_API_TOKEN' => @token, 'HTTP_USER_AGENT' => "Rspec" }
        end

        it 'returns a 200 status' do
          response.status.should == 200
        end

        it 'returns the requests limit headers' do
          headers['X-RateLimit-Limit'].should == "5000"
        end

        it 'decreases the remaining requests' do
          headers['X-RateLimit-Remaining'].should == "4998"
        end
      end
    end
  end
end