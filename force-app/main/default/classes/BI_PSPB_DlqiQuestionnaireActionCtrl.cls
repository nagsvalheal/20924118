/**
* @description  This class provides methods to handle DLQI (Daily Living
Questionnaire Index) related operations. It processes questionnaires
when videos are uploaded, creates tasks, and sends notifications (SMS and
email) as needed.
* History
* Version	Author			Date		Detail		Description
* 1.0		Niyas		24-07-2024		Created		Refactored Version
*/
public with sharing class BI_PSPB_DlqiQuestionnaireActionCtrl {
    /**
	* @description  Processes dlqi questionnaires by creating tasks for due
	* assessments when a video is uploaded. It also sends notifications (SMS
	* and email) to the relevant parties.
	*/
    public static void processDlqiQuestionnaires() {
        try {
            Set<Id> enrolleeIds = BI_PSPB_EnrolleeProcessorCtrl.fetchEnrolleeIds();
            if (!enrolleeIds.isEmpty()) {
                Integer dlqiCount = BI_PSPB_QuestionsDaysCountQueryCtrl.fetchDlqiCount();
                List<Id> enrolleeRecIds = BI_PSPB_SymptomProcessorCtrl.processSymptomTrackers(enrolleeIds, dlqiCount);

                if (!enrolleeRecIds.isEmpty()) {
                    List<CareProgramEnrollee> enrolleeRecords = 
                        BI_PSPB_EnrolleeProcessorCtrl.fetchEnrolleeRecords(enrolleeRecIds);
                        processEnrollees(enrolleeRecords);
                }
            } else {
                BI_PSP_LogMessagesUtility.logError(
                    BI_PSPB_NotificationConstant.errorMsgRecordNotFound,
                    BI_PSPB_DlqiQuestionnaireActionCtrl.class.toString(), false,
                    BI_PSPB_NotificationConstant.severityError);
            }
        } catch (Exception ex) {
            BI_PSP_LogMessagesUtility.logError(
                ex.getMessage(),
                BI_PSPB_DlqiQuestionnaireActionCtrl.class.toString(), false,
                BI_PSPB_NotificationConstant.severityError);
        }
    }
    /**
	* @description This method processes list of enrollees and create tasks.
	* @param enrolleeRecords Enrollee for the notifications to be sent.
    */
	private static void processEnrollees(List<CareProgramEnrollee> enrolleeRecords){
		List<Task> newTaskList = new List<Task>();
		List<Id> sendNotificationIds = new List<Id>();
        List<Id> enrolleeEmailIds;
		for (CareProgramEnrollee enrollee : enrolleeRecords) {
            enrolleeEmailIds = processEnrollee(enrollee, newTaskList);
            if(!enrolleeEmailIds.isEmpty()){
                sendNotificationIds.addAll(enrolleeEmailIds);
            }
        }
        BI_PSP_DatabaseOperationsUtility.insertOperation(newTaskList, BI_PSPB_DlqiQuestionnaireActionCtrl.class.toString(), false);
        sendNotifications(sendNotificationIds);
	}
    /**
	* @description This method processes a single CareProgramEnrollee record to create and
    add tasks to the newTaskList based on the enrollee's age and caregiver status.
	* @param enrollee Enrollee for the questions to retrieve.
    * @param newTaskList List of tasks that are to be created.
    * @return List<Id> Ids for sending notification.
    */
    public static List<Id> processEnrollee(CareProgramEnrollee enrollee, List<Task> newTaskList) {
        List<Id> enrolleeEmailIds = new List<Id>();
        try{
            Date today = Date.today();
            Integer age = BI_PSPB_EnrolleeProcessorCtrl.calculateAge(enrollee.Account.BI_PSP_Birthdate__c, today);
            String patientName = enrollee.Account.Name;
            Id enrolleeId = enrollee.Id;
            Id caregiverId = BI_PSPB_CaregiverProcessorCtrl.fetchCaregiverId(enrolleeId);
            Integer legalAge = Integer.valueOf(BI_PSPB_NotificationConstant.legalAge);
            List<Id> enrolleeSendIds = BI_PSPB_AssessmentProcessorCtrl.fetchDueAssessments(new List<Id>{enrolleeId}, BI_PSPB_NotificationConstant.dlqiQuestionName);
            if ((age > legalAge && caregiverId == null) && !enrolleeSendIds.isEmpty()) {
                enrolleeEmailIds.addAll(enrolleeSendIds);
                    BI_PSPB_TaskParameterCtrl params = new BI_PSPB_TaskParameterCtrl(
                        BI_PSPB_NotificationConstant.dlqiQuestionSubject,
                        BI_PSPB_NotificationConstant.actionTypeAction,
                        BI_PSPB_NotificationConstant.dlqi,
                        '',
                        BI_PSPB_NotificationConstant.actionTypeNotificatonTypeAction
                    );
                    newTaskList.addAll(BI_PSPB_TaskCreatorCtrl.createPatientTasks(enrolleeSendIds, params, BI_PSPB_NotificationConstant.patient, null));
            } else {
                List<Id> caregiverSendIds = BI_PSPB_AssessmentProcessorCtrl.fetchDueAssessments(new List<Id>{enrolleeId}, BI_PSPB_NotificationConstant.dlqiQuestionName);
                if (!caregiverSendIds.isEmpty()) {
                    enrolleeEmailIds.addAll(caregiverSendIds);
                    BI_PSPB_TaskParameterCtrl params = new BI_PSPB_TaskParameterCtrl(
                        BI_PSPB_NotificationConstant.dlqiQuestionSubject,
                        BI_PSPB_NotificationConstant.actionTypeAction,
                        BI_PSPB_NotificationConstant.dlqi,
                        '',
                        BI_PSPB_NotificationConstant.actionTypeNotificatonTypeAction
                    );
                    newTaskList.addAll(BI_PSPB_TaskCreatorCtrl.createPatientTasks(caregiverSendIds, params, BI_PSPB_NotificationConstant.patient, caregiverId));

                    BI_PSPB_TaskParameterCtrl params2 = new BI_PSPB_TaskParameterCtrl(
                        BI_PSPB_NotificationConstant.dlqiCaregiverOne + ' ' + patientName + BI_PSPB_NotificationConstant.dlqiCaregiverTwo,
                        BI_PSPB_NotificationConstant.actionTypeAction,
                        BI_PSPB_NotificationConstant.dlqi,
                        '',
                        BI_PSPB_NotificationConstant.actionTypeNotificatonTypeAction
                    );
                    newTaskList.addAll(BI_PSPB_TaskCreatorCtrl.createCaregiverTasks(caregiverSendIds, params2, BI_PSPB_NotificationConstant.caregiver, caregiverId));
                }
            }
        } catch (Exception ex) {
			BI_PSP_LogMessagesUtility.logError(
				ex.getMessage(),
				BI_PSPB_DlqiQuestionnaireActionCtrl.class.toString(), false,
				BI_PSPB_NotificationConstant.severityError);
		}
        return enrolleeEmailIds;
    }
    /**
    * @description Method is used to send SMS and email notification.
    * @param enrolleeEmailIds Idsto send email
    */
    public static void sendNotifications(List<Id> enrolleeEmailIds) {
        try{
            if (!enrolleeEmailIds.isEmpty()) {
                BI_PSPB_NotificationSender.sendNotifications(enrolleeEmailIds, BI_PSPB_NotificationConstant.dlqi, new List<String>{''});
            }
        } catch (Exception ex) {
            BI_PSP_LogMessagesUtility.exceptionLogMessage(
                ex.getMessage(),
                BI_PSPB_DlqiQuestionnaireActionCtrl.class.getName(),
                ex
            );
        }
    }
}