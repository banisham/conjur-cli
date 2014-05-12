require 'spec_helper'

shared_context "stub config file" do
  before { 
    File.stub(:exists?).with(".conjurenv").and_return(true)
    File.stub(:read).with(".conjurenv").and_return(file_contents)
  }
end

shared_examples_for "rejects malformed file" do
  it 'crashes' do
    api.should_not_receive(:variable)
    api.should_not_receive(:variable_values)
    expect { invoke }.to raise_error /File .* should contain one-level Hash with strings as values/
  end
end

shared_examples_for "reads desired configuration file" do |filename|
  describe "if file does not exist" do
    before { File.should_receive(:exists?).with(filename).and_return { false } }
    it "crashes" do
      expect { invoke }.to raise_error "File does not exist: #{filename}"
    end
  end
  describe "if file is existing" do
    before { 
      File.should_receive(:exists?).with(filename).and_return(true)
      File.should_receive(:read).with(filename).and_return(file_contents) 
    }

    describe "If file is not YAML" do
      let(:file_contents) { "Not a valid YAML" }
      it_behaves_like "rejects malformed file"
    end

    describe "If file contains complex nested YAML" do
      let(:file_contents) { """
--- 
a: 
  b:
    - 'c'
    - 'd'
    - 'e'
"""
      }
      it_behaves_like "rejects malformed file"
    end

    describe "If values are not strings" do
      let(:file_contents) { """
--- 
a: 1
b: 'cd'
"""
      }
      it_behaves_like "rejects malformed file"
    end

    describe "If file is valid" do
      it 'proceeds further' do
        expect { invoke }.to_not raise_error
      end
    end
  end
end

shared_examples_for "reads configuration file" do
  before { 
    api.stub(:variable).and_return(double(value:1))
    api.stub(:variable_values).and_return({"a"=>"b"})
    api.stub(:resource).and_return(double(permitted?:true))
    Kernel.stub(:exec).and_return(true)
  }

  describe "with -f option" do
    let(:file_options) { ["-f", "somefile"] } 
    it_behaves_like "reads desired configuration file", "somefile"
  end
  describe "with --file option" do 
    let(:file_options) { ["--file", "somefile"] } 
    it_behaves_like "reads desired configuration file", "somefile"
  end
  describe "by default .conjurenv file is used" do
    let(:file_options) { [] } 
    it_behaves_like "reads desired configuration file", ".conjurenv"
  end
end

shared_examples_for "launches external command with expected variables" do
  describe "calls #exec with appropriate environment and arguments" do
    let(:expected_environment) {{ "VARIABLE_A"=> 1, "VARIABLE_B" => 2 }}
    describe "without extra args" do
      it "passes external command to #exec" do
        Kernel.should_receive(:exec).with( expected_environment, [ external_command ] ).and_return (true)
        invoke
      end
    end
    describe "with extra args" do
      let(:extra_args) { ["--arg1","val1","--arg2"] }
      it "passes extra args to #exec" do
        Kernel.should_receive(:exec).with( expected_environment, [ external_command ] + extra_args ).and_return(true)
        invoke
      end
    end
  end
end

describe Conjur::Command::Env, logged_in: true do
  describe "env" do

    let(:command) { ["env"] }
    let(:file_options) { [] }     # stub  
    let(:command_options) { [] } #"--","stub"] }  
    let(:external_command) { "external_command" }
    let(:extra_args) { [] }
    let(:file_contents) { """
--- 
variable_a: conjur/variable/1
variable_b: conjur/variable/2
  """
    }
    let(:conjur_variables) { 
      { 
        "conjur/variable/1"=>1,
        "conjur/variable/2"=>2
      }
    }
    let(:invoke) {
      Conjur::CLI.error_device = $stderr
      cmd = command + file_options + command_options + extra_args
      Conjur::CLI.run cmd
    }


    describe "requires either 'check' or 'external command' opion" do
      describe "if both options are provided" do
        let(:command_options) { [ '--check', '--', 'external_command' ] } 
        it "crashes" do 
          expect { invoke }.to raise_error /Options '--check' and '.*' can not be provided together/
        end
      end
      describe "if neither option is provided" do
        let(:command_options) { [] } 
        it "crashes" do 
          expect { invoke }.to raise_error "Either --check or '-- external_command' option should be provided"
        end
      end
    end

    describe "with --check option" do
      it_behaves_like "reads configuration file"  
      include_context "stub config file"
      let(:command_options) { [ "--check" ] }
      it "checks variables one by one" do
        api.should_not_receive(:variable_values)
        api.should_not_receive(:variable)
        api.should_receive(:resource).twice.and_return(double(permitted?:true))
        invoke
      end 
      describe "if all variables are available" do
        before { api.should_receive(:resource).twice.and_return(double(permitted?:true)) }
        it 'prints status' do
          expect { invoke }.to write "conjur/variable/1: available\nconjur/variable/2: available\n"
        end
        it 'does not crash' do
          expect { invoke }.to_not raise_error
        end
      end
      describe "if some variables are available" do 
        before { 
          api.should_receive(:resource).with("variable:conjur/variable/1").and_return(double(permitted?:false))
          api.should_receive(:resource).with("variable:conjur/variable/2").and_return(double(permitted?:true))
        }
        it 'prints status for all variables' do 
          GLI.stub(:exit_now!).and_return { raise "custom exit" }
          expect { invoke rescue true }.to write "conjur/variable/1: not available\nconjur/variable/2: available\n"
        end
        it 'crashes in the end' do
          expect { invoke }.to raise_error "Some variables are not available"
        end
      end
    end

    describe "with '-- external command' option" do
      it_behaves_like "reads configuration file"
      let(:external_command) { "somecommand" }
      let(:command_options) { [ "--", external_command ] }  
      include_context "stub config file"
      describe "if variable_values method succeeds" do  

        before { api.should_receive(:variable_values).with(conjur_variables.keys).and_return(conjur_variables) }

        it "does not call 'variable' method" do
          Kernel.stub(:exec).and_return(true)
          api.should_not_receive(:variable)
          expect { invoke }.to_not raise_error
        end 

        it_behaves_like "launches external command with expected variables"
      end

      describe "if variable_values method fails" do
        before { api.should_receive(:variable_values).with(conjur_variables.keys).and_return { raise RestClient::Forbidden } }

        #it "issues a warning" do
        #  api.stub(:variable).and_return(double(value:1))
        #  Kernel.stub(:exec).and_return(true)
        #  expect { invoke }.to_not raise_error
        #  expect { invoke }.to write("Warning: batch retrieval failed, processing variables one by one").to(:stderr)
        #end

        it "checks variables one by one"  do
          Kernel.stub(:exec).and_return(true)
          api.should_receive(:variable).with("conjur/variable/1").and_return(double(value:1))
          api.should_receive(:variable).with("conjur/variable/2").and_return(double(value:2))
          expect { invoke }.to_not raise_error
        end

        describe "if some variable is unavailable" do
          before { 
            api.should_receive(:variable).with("conjur/variable/1").and_return(double(value:1))
            api.should_receive(:variable).with("conjur/variable/2").and_return { raise RestClient::Forbidden } 
          }
          it "does not call external command and crashes" do
            Kernel.should_not_receive(:exec)
            expect { invoke }.to raise_error RestClient::Forbidden 
          end
        end
        describe "if all variables are available" do
          before { 
            api.should_receive(:variable).with("conjur/variable/1").and_return(double(value:1))
            api.should_receive(:variable).with("conjur/variable/2").and_return(double(value:2))
          }
          it_behaves_like "launches external command with expected variables"
        end
      end
    end

  end
end
