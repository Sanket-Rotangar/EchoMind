const { GoogleGenerativeAI, SchemaType } = require("@google/generative-ai");

// Initialize SDK
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

// Define the STRICT schema the model MUST follow
const meetingSchema = {
    type: SchemaType.OBJECT,
    properties: {
        bottom_line: { 
            type: SchemaType.STRING, 
            description: "The 'CEO Summary'. 2-3 crisp sentences stating the core outcome of the meeting. No fluff." 
        },
        decisions_register: {
            type: SchemaType.ARRAY,
            description: "Concrete decisions that were finalized. DO NOT include tasks here. Only agreed-upon choices or policies. Empty array if none.",
            items: { type: SchemaType.STRING }
        },
        action_matrix: {
            type: SchemaType.ARRAY,
            description: "Specific tasks assigned to individuals.",
            items: {
                type: SchemaType.OBJECT,
                properties: {
                    assignee: { type: SchemaType.STRING, description: "Name/Title of the person. Use 'Unassigned' if vague." },
                    task: { type: SchemaType.STRING, description: "The specific, actionable work to be done." },
                    deadline: { type: SchemaType.STRING, nullable: true, description: "Specific date, day, or time mentioned. Null if none." }
                },
                required: ["assignee", "task"]
            }
        },
        risks_and_blockers: {
            type: SchemaType.ARRAY,
            description: "Any mentioned delays, budget issues, client pushback, or technical roadblocks. Empty array if none.",
            items: { type: SchemaType.STRING }
        },
        key_metrics: {
            type: SchemaType.ARRAY,
            description: "Extract any hard numbers mentioned: Budgets, prices, percentages, quantities, or dates. (e.g., '$50k budget', '20% growth', '400 units'). Empty array if none.",
            items: { type: SchemaType.STRING }
        }
    },
    required: ["bottom_line", "decisions_register", "action_matrix", "risks_and_blockers", "key_metrics"]
};

// Configure the model with the schema
const model = genAI.getGenerativeModel({
    model: "gemini-2.5-flash",
    generationConfig: {
        responseMimeType: "application/json",
        responseSchema: meetingSchema, // <--- THIS IS THE MAGIC LOCK
    }
});

const extractMeetingInsights = async (transcriptArray) => {
    try {
        const transcriptText = transcriptArray.join("\n");
        const prompt = `
            Analyze this meeting transcript. Extract the core objective, definitive action items, and deadlines. 
            Do not invent data. Resolve pronouns to specific speakers.
            
            TRANSCRIPT:
            ${transcriptText}
        `;

        const result = await model.generateContent(prompt);
        const responseText = result.response.text();
        
        // Return the guaranteed JSON object
        return JSON.parse(responseText);
    } catch (error) {
        console.error("Gemini Extraction Error:", error);
        throw error;
    }
};

module.exports = { extractMeetingInsights };