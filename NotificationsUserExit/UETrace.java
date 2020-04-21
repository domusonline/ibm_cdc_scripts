/****************************************************************************
 ** Latest change: 2017 Fernando Nunes
 ** License: This script is licensed as Apache ( http://www.apache.org/licenses/LICENSE-2.0.html )
 ** $Author: Fernando Nunes - domusonline@gmail.com $
 ** $Revision: 1.0.62 $
 ** $Date: 2020-04-21 15:56:09 $
 **
 ** Based on the samples provided by IBM:
 **
 ** Licensed Materials - Property of IBM
 ** IBM InfoSphere Change Data Capture
 ** 5724-U70
 **
 ** (c) Copyright IBM Corp. 2001-2013 All rights reserved.
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
import com.datamirror.ts.util.trace.Trace;

/**
 * Tracing facility for user exit
 */
public class UETrace {
	boolean enabled = false;

	/**
	 * Initializes the tracing facility
	 */
	public void init(boolean enabled) {
		this.enabled = enabled;
	}

	/**
	 * Writes a trace message (always)
	 * 
	 * @param message
	 *            - Messag to write to the trace
	 */
	public void writeAlways(String message) {
		// Piggyback on the CDC logging facility
		System.out.println(message);
		Trace.traceAlways(message);
		return;
	}

	/**
	 * Writes a trace message
	 * 
	 * @param message
	 *            - Messag to write to the trace
	 */
	public void write(String message) {
		if (enabled) {
			writeAlways(message);
		}
		return;
	}

	/**
	 * Cleanup for trace facility -> not used in this implementation
	 */
	public void close() {
	}
}
