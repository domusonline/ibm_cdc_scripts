/****************************************************************************
** Latest change: 2017 Fernando Nunes
** License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
** $Author: Fernando Nunes - domusonline@gmail.com $
** $Revision: 1.0.60 $
** $Date: 2020-04-21 15:55:20 $
** Requires UETrace.java
**
** Based on the samples provided by IBM:
** Licensed Materials - Property of IBM 
** IBM InfoSphere Change Data Capture
** 5724-U70
** 
** (c) Copyright IBM Corp. 2011 All rights reserved.
** 
** The following sample of source code ("Sample") is owned by International 
** Business Machines Corporation or one of its subsidiaries ("IBM") and is 
** copyrighted and licensed, not sold. You may use, copy, modify, and 
** distribute the Sample in any form without payment to IBM.
** 
** The Sample code is provided to you on an "AS IS" basis, without warranty of 
** any kind. IBM HEREBY EXPRESSLY DISCLAIMS ALL WARRANTIES, EITHER EXPRESS OR 
** IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
** MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. Some jurisdictions do 
** not allow for the exclusion or limitation of implied warranties, so the above 
** limitations or exclusions may not apply to you. IBM shall not be liable for 
** any damages you suffer as a result of using, copying, modifying or 
** distributing the Sample, even if IBM has been advised of the possibility of 
** such damages.
*****************************************************************************/

import com.datamirror.ts.api.*;

import java.io.*;
import java.util.*;
import java.text.SimpleDateFormat;

/**
 *
 * AlertFileHandler is an implementation of the AlertHandlerIF.
 */
public class AlertFileHandler implements AlertHandlerIF
{
	public Properties properties;
    
	/**
	* User exit <b>must have</b> constructor with no arguments.
	* Though it would exist by default, it is adduced here for clearness.
	*/
   
	UETrace trace;
	ArrayList<Integer> warningIdList;
	String logFileName;
	String separator;
	Integer minimumCategory;
	Long size;
   
	public AlertFileHandler()
	{
		this.properties = new Properties(); 
		trace = new UETrace();
		trace.init(true);
	   
		this.warningIdList = new ArrayList<Integer>();
	   
		try { 
			String propFileName = System.getenv("ALERT_PROP_FILE");
			if (propFileName == null)
			{
				propFileName = "alertfile.properties";
				trace.writeAlways("Notification UE: ALERT_PROP_FILE env variable couldn't be found. Defaulting properties file to alertfile.properties");
			}
			properties.load(new FileInputStream(propFileName)); 		      
		} 
		catch (IOException e) 
		{ 
			properties.setProperty("file", "iidr_alert_file.log");
			properties.setProperty("size", "10000");
			properties.setProperty("separator", "|");
			properties.setProperty("warning_ids", "");
			properties.setProperty("minimum_category","5");
		} 
	   
		this.logFileName = properties.getProperty("file", "iidr_alert_file.log"); 
		this.separator = properties.getProperty("separator","|");
		this.size = new Long(properties.getProperty("size", "10000"));
		String warningIDs = properties.getProperty("warning_ids","");
		this.minimumCategory = new Integer(properties.getProperty("minimum_category","5"));
		  
		if (!warningIDs.equalsIgnoreCase(""))
		{
			String[] tmpWarnings = warningIDs.split(",");
		   
			for (int i = 0; i < tmpWarnings.length; ++i)
			{
				this.warningIdList.add(new Integer(tmpWarnings[i].trim()));
			}
		}
	}

	public void handle(int p_zoneID, int p_categoryID, String p_SourceOrTarget, String p_Name, int p_EventID, String p_EventText, Properties p_OtherInfo) throws Exception
	{
		try {
			String[] zones = { "", "Scrape/Refresh","Communication","Environment","Journal","Communication","Apply","Environment"  };
			String[] categories = { "", "Fatal","Error","Information","Status","Operational","Warning" };
	  
			int newCategoryID = p_categoryID;
	  
			if (this.warningIdList.contains(p_EventID))
			{
				newCategoryID = 6;
			} 
	  
			if ( (newCategoryID == 6) || (newCategoryID <= this.minimumCategory) )
			{
				FileOutputStream fos = new FileOutputStream(this.logFileName, true);
     	 
				OutputStreamWriter osw = new OutputStreamWriter(fos);
				BufferedWriter bw = new BufferedWriter(osw);


				/*Time*/
				Calendar Cal    = new GregorianCalendar(new Locale("en","US"));
				Cal.setTime(new Date());
				SimpleDateFormat DF = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

				int tmpZoneID = p_zoneID;
				if (p_SourceOrTarget.equals("T"))
				{
					tmpZoneID += 4; 
				}

				String msg = DF.format(Cal.getTime())+separator+p_SourceOrTarget+this.separator+p_Name+this.separator+p_EventID+this.separator+categories[newCategoryID]+this.separator+zones[tmpZoneID]+this.separator+p_EventText+"\n";
				bw.write(msg);


				bw.close();
				osw.close();
				fos.close();
     	 
				SimpleDateFormat DF2 = new SimpleDateFormat("yyyy-MM-dd_HH:mm:ss");
     	 
				File file = new File(this.logFileName); 
     	 
				if (file.length() > this.size.longValue()*1024)
				{
					File newFile = new File(this.logFileName+"_"+DF2.format(new Date())+".log");
					file.renameTo(newFile);
				}
			}
		} catch (Exception e)
		{
			e.printStackTrace();
			trace.writeAlways(e.getMessage());
		}
		return ;
	}
}
