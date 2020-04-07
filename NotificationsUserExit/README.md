# Notification User Exit

This is a working example of a notification user exit for IBM InfoSphere Data Replication agents on distributed systems
For more examples (notification user exits and others) please visit:

[https://www.ibm.com/support/pages/node/1105107](https://www.ibm.com/support/pages/node/1105107 "IIDR samples")

###Introdution
This is a very simple example, based on other sample previously made available by IBM.
That previous example was partially improved/merged to achieve better functionality

###Distribution and license
The samples can be used, modified and distributed by anyone. The code from IBM is copyrighted by IBM.

###Disclaimer
The code and examples are provided AS IS. No guaranties of any sort are provided. Use at your own risk<br/>

###Support
As stated in the disclaimer section above, the scripts are provided AS IS. The author will not guarantee any sort of support but you can reach out to me for doubts, suggestions etc.

###Compiling the handler
The compilation is very simple and "crude". Just copy the asset *.java files, setup a JDK environment and run:

javac -cp IIDR_INSTALL_DIR/lib/ts.jar AlertFileHandler.java UETrace.java

###Installation and configuration
1- Copy the *.class files into IIDR_INSTALL_DIR/lib/user
2- Copy the alertfile.properties file to the instance "conf" directory or to any other place pointed by ALERT_PROP_FILE environment variable
3- Use Management Console (GUI) to configure the AlertFileHandler class for notifications
4- Try it


###list of assets published

- AlertFileHandler.java<br/>The implementation of the Notification user exit handler (main file)

- UETrace.java<br/>Auxiliary file for the interface implementation

- alertfile.properties<br/>example configuration file


