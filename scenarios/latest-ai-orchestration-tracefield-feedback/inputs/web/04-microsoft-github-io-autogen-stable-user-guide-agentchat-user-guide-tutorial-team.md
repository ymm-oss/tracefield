---
kind: web_page
source_url: "https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html"
title: "Teams &#8212; AutoGen"
fetched_at: "2026-06-16T23:33:24.691284+00:00"
content_type: "text/html; charset=utf-8"
bytes: 96858
---

# Teams &#8212; AutoGen

Source: https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html
Fetched: 2026-06-16T23:33:24.691284+00:00

Teams &#8212; AutoGen
Skip to main content
Back to top
Ctrl + K
Choose version
AgentChat
Core
Extensions
Studio
API Reference
.NET
More
0.2 Docs
Search
Ctrl + K
GitHub
Discord
Twitter
Search
Ctrl + K
AgentChat
Core
Extensions
Studio
API Reference
.NET
0.2 Docs
GitHub
Discord
Twitter
Installation
Quickstart
Migration Guide for v0.2 to v0.4
Tutorial
Introduction
Models
Messages
Agents
Teams
Human-in-the-Loop
Termination
Managing State
Advanced
Custom Agents
Selector Group Chat
Swarm
Magentic-One
GraphFlow (Workflows)
Memory and RAG
Logging
Serializing Components
Tracing and Observability
More
Examples
Travel Planning
Company Research
Literature Review
API Reference
PyPi
Source
AgentChat
Teams
Teams #
In this section you’ll learn how to create a multi-agent team (or simply team) using AutoGen. A team is a group of agents that work together to achieve a common goal.
We’ll first show you how to create and run a team. We’ll then explain how to observe the team’s behavior, which is crucial for debugging and understanding the team’s performance, and common operations to control the team’s behavior.
AgentChat supports several team presets:
RoundRobinGroupChat : A team that runs a group chat with participants taking turns in a round-robin fashion (covered on this page). Tutorial
SelectorGroupChat : A team that selects the next speaker using a ChatCompletion model after each message. Tutorial
MagenticOneGroupChat : A generalist multi-agent system for solving open-ended web and file-based tasks across a variety of domains. Tutorial
Swarm : A team that uses HandoffMessage to signal transitions between agents. Tutorial
Note
When should you use a team?
Teams are for complex tasks that require collaboration and diverse expertise.
However, they also demand more scaffolding to steer compared to single agents.
While AutoGen simplifies the process of working with teams, start with
a single agent for simpler tasks, and transition to a multi-agent team when a single agent proves inadequate.
Ensure that you have optimized your single agent with the appropriate tools
and instructions before moving to a team-based approach.
Creating a Team #
RoundRobinGroupChat is a simple yet effective team configuration where all agents share the same context and take turns responding in a round-robin fashion. Each agent, during its turn, broadcasts its response to all other agents, ensuring that the entire team maintains a consistent context.
We will begin by creating a team with two AssistantAgent and a TextMentionTermination condition that stops the team when a specific word is detected in the agent’s response.
The two-agent team implements the reflection pattern, a multi-agent design pattern where a critic agent evaluates the responses of a primary agent. Learn more about the reflection pattern using the Core API .
import asyncio
from autogen_agentchat.agents import AssistantAgent
from autogen_agentchat.base import TaskResult
from autogen_agentchat.conditions import ExternalTermination , TextMentionTermination
from autogen_agentchat.teams import RoundRobinGroupChat
from autogen_agentchat.ui import Console
from autogen_core import CancellationToken
from autogen_ext.models.openai import OpenAIChatCompletionClient
# Create an OpenAI model client.
model_client = OpenAIChatCompletionClient (
model = "gpt-4o-2024-08-06" ,
# api_key="sk-...", # Optional if you have an OPENAI_API_KEY env variable set.
)
# Create the primary agent.
primary_agent = AssistantAgent (
"primary" ,
model_client = model_client ,
system_message = "You are a helpful AI assistant." ,
)
# Create the critic agent.
critic_agent = AssistantAgent (
"critic" ,
model_client = model_client ,
system_message = "Provide constructive feedback. Respond with 'APPROVE' to when your feedbacks are addressed." ,
)
# Define a termination condition that stops the task if the critic approves.
text_termination = TextMentionTermination ( "APPROVE" )
# Create a team with the primary and critic agents.
team = RoundRobinGroupChat ([ primary_agent , critic_agent ], termination_condition = text_termination )
Running a Team #
Let’s call the run() method
to start the team with a task.
# Use `asyncio.run(...)` when running in a script.
result = await team . run ( task = "Write a short poem about the fall season." )
print ( result )
TaskResult(messages=[TextMessage(source='user', models_usage=None, content='Write a short poem about the fall season.', type='TextMessage'), TextMessage(source='primary', models_usage=RequestUsage(prompt_tokens=28, completion_tokens=109), content="Leaves of amber, gold, and rust, \nDance upon the gentle gust. \nCrisp air whispers tales of old, \nAs daylight wanes, the night grows bold. \n\nPumpkin patch and apple treats, \nLaughter in the street repeats. \nSweaters warm and fires aglow, \nIt's time for nature's vibrant show. \n\nThe harvest moon ascends the sky, \nWhile geese in formation start to fly. \nAutumn speaks in colors bright, \nA fleeting grace, a pure delight. ", type='TextMessage'), TextMessage(source='critic', models_usage=RequestUsage(prompt_tokens=154, completion_tokens=200), content='Your poem beautifully captures the essence of the fall season with vivid imagery and a rhythmic flow. The use of descriptive language like "amber, gold, and rust" effectively paints a visual picture of the changing leaves. Phrases such as "crisp air whispers tales of old" and "daylight wanes, the night grows bold" add a poetic touch by incorporating seasonal characteristics.\n\nHowever, you might consider exploring other sensory details to deepen the reader\'s immersion. For example, mentioning the sound of crunching leaves underfoot or the scent of cinnamon and spices in the air could enhance the sensory experience.\n\nAdditionally, while the mention of "pumpkin patch and apple treats" is evocative of fall, expanding on these elements or including more personal experiences or emotions associated with the season might make the poem more relatable and engaging.\n\nOverall, you\'ve crafted a lovely poem that celebrates the beauty and traditions of autumn with grace and warmth. A few tweaks to include multisensory details could elevate it even further.', type='TextMessage'), TextMessage(source='primary', models_usage=RequestUsage(prompt_tokens=347, completion_tokens=178), content="Thank you for the thoughtful feedback. Here's a revised version of the poem with additional sensory details:\n\nLeaves of amber, gold, and rust, \nDance upon the gentle gust. \nCrisp air whispers tales of old, \nAs daylight wanes, the night grows bold. \n\nCrunch beneath the wandering feet, \nA melody of autumn's beat. \nCinnamon and spices blend, \nIn every breeze, nostalgia sends. \n\nPumpkin patch and apple treats, \nLaughter in the street repeats. \nSweaters warm and fires aglow, \nIt's time for nature's vibrant show. \n\nThe harvest moon ascends the sky, \nWhile geese in formation start to fly. \nAutumn speaks in colors bright, \nA fleeting grace, a pure delight. \n\nI hope this version resonates even more with the spirit of fall. Thank you again for your suggestions!", type='TextMessage'), TextMessage(source='critic', models_usage=RequestUsage(prompt_tokens=542, completion_tokens=3), content='APPROVE', type='TextMessage')], stop_reason="Text 'APPROVE' mentioned")
The team runs the agents until the termination condition was met.
In this case, the team ran agents following a round-robin order until the the
termination condition was met when the word “APPROVE” was detected in the
agent’s response.
When the team stops, it returns a TaskResult object with all the messages produced by the agents in the team.
Observing a Team #
Similar to the agent’s on_messages_stream() method, you can stream the team’s messages while it is running by calling the run_stream() method. This method returns a generator that yields messages produced by the agents in the team as they are generated, with the final item being the TaskResult object.
# When running inside a script, use a async main function and call it from `asyncio.run(...)`.
await team . reset () # Reset the team for a new task.
async for message in team . run_stream ( task = "Write a short poem about the fall season." ): # type: ignore
if isinstance ( message , TaskResult ):
print ( "Stop Reason:" , message . stop_reason )
else :
print ( message )
source='user' models_usage=None content='Write a short poem about the fall season.' type='TextMessage'
source='primary' models_usage=RequestUsage(prompt_tokens=28, completion_tokens=105) content="Leaves descend in golden dance, \nWhispering secrets as they fall, \nCrisp air brings a gentle trance, \nHeralding Autumn's call. \n\nPumpkins glow with orange light, \nFields wear a cloak of amber hue, \nDays retreat to longer night, \nSkies shift to deeper blue. \n\nWinds carry scents of earth and pine, \nSweaters wrap us, warm and tight, \nNature's canvas, bold design, \nIn Fall's embrace, we find delight. " type='TextMessage'
source='critic' models_usage=RequestUsage(prompt_tokens=150, completion_tokens=226) content='Your poem beautifully captures the essence of fall with vivid imagery and a soothing rhythm. The imagery of leaves descending, pumpkins glowing, and fields cloaked in amber hues effectively paints a picture of the autumn season. The use of contrasting elements like "Days retreat to longer night" and "Sweaters wrap us, warm and tight" provides a nice balance between the cold and warmth associated with the season. Additionally, the personification of autumn through phrases like "Autumn\'s call" and "Nature\'s canvas, bold design" adds depth to the depiction of fall.\n\nTo enhance the poem further, you might consider focusing on the soundscape of fall, such as the rustling of leaves or the distant call of migrating birds, to engage readers\' auditory senses. Also, varying the line lengths slightly could add a dynamic flow to the reading experience.\n\nOverall, your poem is engaging and effectively encapsulates the beauty and transition of fall. With a few adjustments to explore other sensory details, it could become even more immersive. \n\nIf you incorporate some of these suggestions or find another way to expand the sensory experience, please share your update!' type='TextMessage'
source='primary' models_usage=RequestUsage(prompt_tokens=369, completion_tokens=143) content="Thank you for the thoughtful critique and suggestions. Here's a revised version of the poem with added attention to auditory senses and varied line lengths:\n\nLeaves descend in golden dance, \nWhisper secrets in their fall, \nBreezes hum a gentle trance, \nHeralding Autumn's call. \n\nPumpkins glow with orange light, \nAmber fields beneath wide skies, \nDays retreat to longer night, \nChill winds and distant cries. \n\nRustling whispers of the trees, \nSweaters wrap us, snug and tight, \nNature's canvas, bold and free, \nIn Fall's embrace, pure delight. \n\nI appreciate your feedback and hope this version better captures the sensory richness of the season!" type='TextMessage'
source='critic' models_usage=RequestUsage(prompt_tokens=529, completion_tokens=160) content='Your revised poem is a beautiful enhancement of the original. By incorporating auditory elements such as "Breezes hum" and "Rustling whispers of the trees," you\'ve added an engaging soundscape that draws the reader deeper into the experience of fall. The varied line lengths work well to create a more dynamic rhythm throughout the poem, adding interest and variety to each stanza.\n\nThe succinct, yet vivid, lines of "Chill winds and distant cries" wonderfully evoke the atmosphere of the season, adding a touch of mystery and depth. The final stanza wraps up the poem nicely, celebrating the complete sensory embrace of fall with lines like "Nature\'s canvas, bold and free."\n\nYou\'ve successfully infused more sensory richness into the poem, enhancing its overall emotional and atmospheric impact. Great job on the revisions!\n\nAPPROVE' type='TextMessage'
Stop Reason: Text 'APPROVE' mentioned
As demonstrated in the example above, you can determine the reason why the team stopped by checking the stop_reason attribute.
The Console() method provides a convenient way to print messages to the console with proper formatting.
await team . reset () # Reset the team for a new task.
await Console ( team . run_stream ( task = "Write a short poem about the fall season." )) # Stream the messages to the console.
---------- user ----------
Write a short poem about the fall season.
---------- primary ----------
Golden leaves in crisp air dance,
Whispering tales as they prance.
Amber hues paint the ground,
Nature's symphony all around.
Sweaters hug with tender grace,
While pumpkins smile, a warm embrace.
Chill winds hum through towering trees,
A vibrant tapestry in the breeze.
Harvest moons in twilight glow,
Casting magic on fields below.
Fall's embrace, a gentle call,
To savor beauty before snowfalls.
[Prompt tokens: 28, Completion tokens: 99]
---------- critic ----------
Your poem beautifully captures the essence of the fall season, creating a vivid and cozy atmosphere. The imagery of golden leaves and amber hues paints a picturesque scene that many can easily relate to. I particularly appreciate the personification of pumpkins and the gentle embrace of sweaters, which adds warmth to your verses.
To enhance the poem further, you might consider adding more sensory details to make the reader feel even more immersed in the experience. For example, including specific sounds, scents, or textures could deepen the connection to autumn's ambiance. Additionally, you could explore the emotional transitions as the season prepares for winter to provide a reflective element to the piece.
Overall, it's a lovely and evocative depiction of fall, evoking feelings of comfort and appreciation for nature's changing beauty. Great work!
[Prompt tokens: 144, Completion tokens: 157]
---------- primary ----------
Thank you for your thoughtful feedback! I'm glad you enjoyed the imagery and warmth in the poem. To enhance the sensory experience and emotional depth, here's a revised version incorporating your suggestions:
---
Golden leaves in crisp air dance,
Whispering tales as they prance.
Amber hues paint the crunchy ground,
Nature's symphony all around.
Sweaters hug with tender grace,
While pumpkins grin, a warm embrace.
Chill winds hum through towering trees,
Crackling fires warm the breeze.
Apples in the orchard's glow,
Sweet cider scents that overflow.
Crunch of paths beneath our feet,
Cinnamon spice and toasty heat.
Harvest moons in twilight's glow,
Casting magic on fields below.
Fall's embrace, a gentle call,
Reflects on life's inevitable thaw.
---
I hope this version enhances the sensory and emotional elements of the season. Thank you again for your insights!
[Prompt tokens: 294, Completion tokens: 195]
---------- critic ----------
APPROVE
[Prompt tokens: 506, Completion tokens: 4]
---------- Summary ----------
Number of messages: 5
Finish reason: Text 'APPROVE' mentioned
Total prompt tokens: 972
Total completion tokens: 455
Duration: 11.78 seconds
TaskResult(messages=[TextMessage(source='user', models_usage=None, content='Write a short poem about the fall season.', type='TextMessage'), TextMessage(source='primary', models_usage=RequestUsage(prompt_tokens=28, completion_tokens=99), content="Golden leaves in crisp air dance, \nWhispering tales as they prance. \nAmber hues paint the ground, \nNature's symphony all around. \n\nSweaters hug with tender grace, \nWhile pumpkins smile, a warm embrace. \nChill winds hum through towering trees, \nA vibrant tapestry in the breeze. \n\nHarvest moons in twilight glow, \nCasting magic on fields below. \nFall's embrace, a gentle call, \nTo savor beauty before snowfalls. ", type='TextMessage'), TextMessage(source='critic', models_usage=RequestUsage(prompt_tokens=144, completion_tokens=157), content="Your poem beautifully captures the essence of the fall season, creating a vivid and cozy atmosphere. The imagery of golden leaves and amber hues paints a picturesque scene that many can easily relate to. I particularly appreciate the personification of pumpkins and the gentle embrace of sweaters, which adds warmth to your verses. \n\nTo enhance the poem further, you might consider adding more sensory details to make the reader feel even more immersed in the experience. For example, including specific sounds, scents, or textures could deepen the connection to autumn's ambiance. Additionally, you could explore the emotional transitions as the season prepares for winter to provide a reflective element to the piece.\n\nOverall, it's a lovely and evocative depiction of fall, evoking feelings of comfort and appreciation for nature's changing beauty. Great work!", type='TextMessage'), TextMessage(source='primary', models_usage=RequestUsage(prompt_tokens=294, completion_tokens=195), content="Thank you for your thoughtful feedback! I'm glad you enjoyed the imagery and warmth in the poem. To enhance the sensory experience and emotional depth, here's a revised version incorporating your suggestions:\n\n---\n\nGolden leaves in crisp air dance, \nWhispering tales as they prance. \nAmber hues paint the crunchy ground, \nNature's symphony all around. \n\nSweaters hug with tender grace, \nWhile pumpkins grin, a warm embrace. \nChill winds hum through towering trees, \nCrackling fires warm the breeze. \n\nApples in the orchard's glow, \nSweet cider scents that overflow. \nCrunch of paths beneath our feet, \nCinnamon spice and toasty heat. \n\nHarvest moons in twilight's glow, \nCasting magic on fields below. \nFall's embrace, a gentle call, \nReflects on life's inevitable thaw. \n\n--- \n\nI hope this version enhances the sensory and emotional elements of the season. Thank you again for your insights!", type='TextMessage'), TextMessage(source='critic', models_usage=RequestUsage(prompt_tokens=506, completion_tokens=4), content='APPROVE', type='TextMessage')], stop_reason="Text 'APPROVE' mentioned")
Resetting a Team #
You can reset the team by calling the reset() method. This method will clear the team’s state, including all agents.
It will call the each agent’s on_reset() method to clear the agent’s state.
await team . reset () # Reset the team for the next run.
It is usually a good idea to reset the team if the next task is not related to the previous task.
However, if the next task is related to the previous task, you don’t need to reset and you can instead
resume the team.
Stopping a Team #
Apart from automatic termination conditions such as TextMentionTermination
that stops the team based on the internal state of the team, you can also stop the team
from outside by using the ExternalTermination .
Calling set()
on ExternalTermination will stop
the team when the current agent’s turn is over.
Thus, the team may not stop immediately.
This allows the current agent to finish its turn and broadcast the final message to the team
before the team stops, keeping the team’s state consistent.
# Create a new team with an external termination condition.
external_termination = ExternalTermination ()
team = RoundRobinGroupChat (
[ primary_agent , critic_agent ],
termination_condition = external_termination | text_termination , # Use the bitwise OR operator to combine conditions.
)
# Run the team in a background task.
run = asyncio . create_task ( Console ( team . run_stream ( task = "Write a short poem about the fall season." )))
# Wait for some time.
await asyncio . sleep ( 0.1 )
# Stop the team.
external_termination . set ()
# Wait for the team to finish.
await run
---------- user ----------
Write a short poem about the fall season.
---------- primary ----------
Leaves of amber, gold, and red,
Gently drifting from trees overhead.
Whispers of wind through the crisp, cool air,
Nature's canvas painted with care.
Harvest moons and evenings that chill,
Fields of plenty on every hill.
Sweaters wrapped tight as twilight nears,
Fall's charming embrace, as warm as it appears.
Pumpkins aglow with autumn's light,
Harvest feasts and stars so bright.
In every leaf and breeze that calls,
We find the magic of glorious fall.
[Prompt tokens: 28, Completion tokens: 114]
---------- Summary ----------
Number of messages: 2
Finish reason: External termination requested
Total prompt tokens: 28
Total completion tokens: 114
Duration: 1.71 seconds
TaskResult(messages=[TextMessage(source='user', models_usage=None, content='Write a short poem about the fall season.', type='TextMessage'), TextMessage(source='primary', models_usage=RequestUsage(prompt_tokens=28, completion_tokens=114), content="Leaves of amber, gold, and red, \nGently drifting from trees overhead. \nWhispers of wind through the crisp, cool air, \nNature's canvas painted with care. \n\nHarvest moons and evenings that chill, \nFields of plenty on every hill. \nSweaters wrapped tight as twilight nears, \nFall's charming embrace, as warm as it appears. \n\nPumpkins aglow with autumn's light, \nHarvest feasts and stars so bright. \nIn every leaf and breeze that calls, \nWe find the magic of glorious fall. ", type='TextMessage')], stop_reason='External termination requested')
From the ouput above, you can see the team stopped because the external termination condition was met,
but the speaking agent was able to finish its turn before the team stopped.
Resuming a Team #
Teams are stateful and maintains the conversation history and context
after each run, unless you reset the team.
You can resume a team to continue from where it left off by calling the run() or run_stream() method again
without a new task.
RoundRobinGroupChat will continue from the next agent in the round-robin order.
await Console ( team . run_stream ()) # Resume the team to continue the last task.
---------- critic ----------
This poem beautifully captures the essence of the fall season with vivid imagery and a soothing rhythm. The descriptions of the changing leaves, cool air, and various autumn traditions make it easy for readers to envision and feel the charm of fall. Here are a few suggestions to enhance its impact:
1. **Structure Variation**: Consider breaking some lines with a hyphen or ellipsis for dramatic effect or emphasis. For instance, “Sweaters wrapped tight as twilight nears— / Fall’s charming embrace, as warm as it appears."
2. **Sensory Details**: While the poem already evokes visual and tactile senses, incorporating other senses such as sound or smell could deepen the immersion. For example, include the scent of wood smoke or the crunch of leaves underfoot.
3. **Metaphorical Language**: Adding metaphors or similes can further enrich the imagery. For example, you might compare the leaves falling to a golden rain or the chill in the air to a gentle whisper.
Overall, it’s a lovely depiction of fall. These suggestions are minor tweaks that might elevate the reader's experience even further. Nice work!
Let me know if these feedbacks are addressed.
[Prompt tokens: 159, Completion tokens: 237]
---------- primary ----------
Thank you for the thoughtful feedback! Here’s a revised version, incorporating your suggestions:
Leaves of amber, gold—drifting like dreams,
A golden rain from trees’ canopies.
Whispers of wind—a gentle breath,
Nature’s scented tapestry embracing earth.
Harvest moons rise as evenings chill,
Fields of plenty paint every hill.
Sweaters wrapped tight as twilight nears—
Fall’s embrace, warm as whispered years.
Pumpkins aglow with autumn’s light,
Crackling leaves underfoot in flight.
In every leaf and breeze that calls,
We find the magic of glorious fall.
I hope these changes enhance the imagery and sensory experience. Thank you again for your feedback!
[Prompt tokens: 389, Completion tokens: 150]
---------- critic ----------
Your revisions have made the poem even more evocative and immersive. The use of sensory details, such as "whispers of wind" and "crackling leaves," beautifully enriches the poem, engaging multiple senses. The metaphorical language, like "a golden rain from trees’ canopies" and "Fall’s embrace, warm as whispered years," adds depth and enhances the emotional warmth of the poem. The structural variation with the inclusion of dashes effectively adds emphasis and flow.
Overall, these changes bring greater vibrancy and life to the poem, allowing readers to truly experience the wonders of fall. Excellent work on the revisions!
APPROVE
[Prompt tokens: 556, Completion tokens: 132]
---------- Summary ----------
Number of messages: 3
Finish reason: Text 'APPROVE' mentioned
Total prompt tokens: 1104
Total completion tokens: 519
Duration: 9.79 seconds
TaskResult(messages=[TextMessage(source='critic', models_usage=RequestUsage(prompt_tokens=159, completion_tokens=237), content='This poem beautifully captures the essence of the fall season with vivid imagery and a soothing rhythm. The descriptions of the changing leaves, cool air, and various autumn traditions make it easy for readers to envision and feel the charm of fall. Here are a few suggestions to enhance its impact:\n\n1. **Structure Variation**: Consider breaking some lines with a hyphen or ellipsis for dramatic effect or emphasis. For instance, “Sweaters wrapped tight as twilight nears— / Fall’s charming embrace, as warm as it appears."\n\n2. **Sensory Details**: While the poem already evokes visual and tactile senses, incorporating other senses such as sound or smell could deepen the immersion. For example, include the scent of wood smoke or the crunch of leaves underfoot.\n\n3. **Metaphorical Language**: Adding metaphors or similes can further enrich the imagery. For example, you might compare the leaves falling to a golden rain or the chill in the air to a gentle whisper.\n\nOverall, it’s a lovely depiction of fall. These suggestions are minor tweaks that might elevate the reader\'s experience even further. Nice work!\n\nLet me know if these feedbacks are addressed.', type='TextMessage'), TextMessage(source='primary', models_usage=RequestUsage(prompt_tokens=389, completion_tokens=150), content='Thank you for the thoughtful feedback! Here’s a revised version, incorporating your suggestions: \n\nLeaves of amber, gold—drifting like dreams, \nA golden rain from trees’ canopies. \nWhispers of wind—a gentle breath, \nNature’s scented tapestry embracing earth. \n\nHarvest moons rise as evenings chill, \nFields of plenty paint every hill. \nSweaters wrapped tight as twilight nears— \nFall’s embrace, warm as whispered years. \n\nPumpkins aglow with autumn’s light, \nCrackling leaves underfoot in flight. \nIn every leaf and breeze that calls, \nWe find the magic of glorious fall. \n\nI hope these changes enhance the imagery and sensory experience. Thank you again for your feedback!', type='TextMessage'), TextMessage(source='critic', models_usage=RequestUsage(prompt_tokens=556, completion_tokens=132), content='Your revisions have made the poem even more evocative and immersive. The use of sensory details, such as "whispers of wind" and "crackling leaves," beautifully enriches the poem, engaging multiple senses. The metaphorical language, like "a golden rain from trees’ canopies" and "Fall’s embrace, warm as whispered years," adds depth and enhances the emotional warmth of the poem. The structural variation with the inclusion of dashes effectively adds emphasis and flow. \n\nOverall, these changes bring greater vibrancy and life to the poem, allowing readers to truly experience the wonders of fall. Excellent work on the revisions!\n\nAPPROVE', type='TextMessage')], stop_reason="Text 'APPROVE' mentioned")
You can see the team resumed from where it left off in the output above,
and the first message is from the next agent after the last agent that spoke
before the team stopped.
Let’s resume the team again with a new task while keeping the context about the previous task.
# The new task is to translate the same poem to Chinese Tang-style poetry.
await Console ( team . run_stream ( task = "将这首诗用中文唐诗风格写一遍。" ))
---------- user ----------
将这首诗用中文唐诗风格写一遍。
---------- primary ----------
朔风轻拂叶飘金，
枝上斜阳染秋林。
满山丰收人欢喜，
月明归途衣渐紧。
南瓜影映灯火中，
落叶沙沙伴归程。
片片秋意随风起，
秋韵悠悠心自明。
[Prompt tokens: 700, Completion tokens: 77]
---------- critic ----------
这首改编的唐诗风格诗作成功地保留了原诗的意境与情感，体现出秋季特有的氛围和美感。通过“朔风轻拂叶飘金”、“枝上斜阳染秋林”等意象，生动地描绘出了秋天的景色，与唐诗中的自然意境相呼应。且“月明归途衣渐紧”、“落叶沙沙伴归程”让人感受到秋天的安宁与温暖。
通过这些诗句，读者能够感受到秋天的惬意与宁静，勾起丰收与团圆的画面，是一次成功的翻译改编。
APPROVE
[Prompt tokens: 794, Completion tokens: 161]
---------- Summary ----------
Number of messages: 3
Finish reason: Text 'APPROVE' mentioned
Total prompt tokens: 1494
Total completion tokens: 238
Duration: 3.89 seconds
TaskResult(messages=[TextMessage(source='user', models_usage=None, content='将这首诗用中文唐诗风格写一遍。', type='TextMessage'), TextMessage(source='primary', models_usage=RequestUsage(prompt_tokens=700, completion_tokens=77), content='朔风轻拂叶飘金， \n枝上斜阳染秋林。 \n满山丰收人欢喜， \n月明归途衣渐紧。 \n\n南瓜影映灯火中， \n落叶沙沙伴归程。 \n片片秋意随风起， \n秋韵悠悠心自明。 ', type='TextMessage'), TextMessage(source='critic', models_usage=RequestUsage(prompt_tokens=794, completion_tokens=161), content='这首改编的唐诗风格诗作成功地保留了原诗的意境与情感，体现出秋季特有的氛围和美感。通过“朔风轻拂叶飘金”、“枝上斜阳染秋林”等意象，生动地描绘出了秋天的景色，与唐诗中的自然意境相呼应。且“月明归途衣渐紧”、“落叶沙沙伴归程”让人感受到秋天的安宁与温暖。\n\n通过这些诗句，读者能够感受到秋天的惬意与宁静，勾起丰收与团圆的画面，是一次成功的翻译改编。\n\nAPPROVE', type='TextMessage')], stop_reason="Text 'APPROVE' mentioned")
Aborting a Team #
You can abort a call to run() or run_stream()
during execution by setting a CancellationToken passed to the cancellation_token parameter.
Different from stopping a team, aborting a team will immediately stop the team and raise a CancelledError exception.
Note
The caller will get a CancelledError exception when the team is aborted.
# Create a cancellation token.
cancellation_token = CancellationToken ()
# Use another coroutine to run the team.
run = asyncio . create_task (
team . run (
task = "Translate the poem to Spanish." ,
cancellation_token = cancellation_token ,
)
)
# Cancel the run.
cancellation_token . cancel ()
try :
result = await run # This will raise a CancelledError.
except asyncio . CancelledError :
print ( "Task was cancelled." )
Task was cancelled.
Single-Agent Team #
Note
Starting with version 0.6.2, you can use AssistantAgent
with max_tool_iterations to run the agent with multiple iterations
of tool calls. So you may not need to use a single-agent team if you just
want to run the agent in a tool-calling loop.
Often, you may want to run a single agent in a team configuration.
This is useful for running the AssistantAgent in a loop
until a termination condition is met.
This is different from running the AssistantAgent using
its run() or run_stream() method,
which only runs the agent for one step and returns the result.
See AssistantAgent for more details about a single step.
Here is an example of running a single agent in a RoundRobinGroupChat team configuration
with a TextMessageTermination condition.
The task is to increment a number until it reaches 10 using a tool.
The agent will keep calling the tool until the number reaches 10,
and then it will return a final TextMessage
which will stop the run.
from autogen_agentchat.agents import AssistantAgent
from autogen_agentchat.conditions import TextMessageTermination
from autogen_agentchat.teams import RoundRobinGroupChat
from autogen_agentchat.ui import Console
from autogen_ext.models.openai import OpenAIChatCompletionClient
model_client = OpenAIChatCompletionClient (
model = "gpt-4o" ,
# api_key="sk-...", # Optional if you have an OPENAI_API_KEY env variable set.
# Disable parallel tool calls for this example.
parallel_tool_calls = False , # type: ignore
)
# Create a tool for incrementing a number.
def increment_number ( number : int ) -> int :
"""Increment a number by 1."""
return number + 1
# Create a tool agent that uses the increment_number function.
looped_assistant = AssistantAgent (
"looped_assistant" ,
model_client = model_client ,
tools = [ increment_number ], # Register the tool.
system_message = "You are a helpful AI assistant, use the tool to increment the number." ,
)
# Termination condition that stops the task if the agent responds with a text message.
termination_condition = TextMessageTermination ( "looped_assistant" )
# Create a team with the looped assistant agent and the termination condition.
team = RoundRobinGroupChat (
[ looped_assistant ],
termination_condition = termination_condition ,
)
# Run the team with a task and print the messages to the console.
async for message in team . run_stream ( task = "Increment the number 5 to 10." ): # type: ignore
print ( type ( message ) . __name__ , message )
await model_client . close ()
TextMessage source='user' models_usage=None metadata={} content='Increment the number 5 to 10.' type='TextMessage'
ToolCallRequestEvent source='looped_assistant' models_usage=RequestUsage(prompt_tokens=75, completion_tokens=15) metadata={} content=[FunctionCall(id='call_qTDXSouN3MtGDqa8l0DM1ciD', arguments='{"number":5}', name='increment_number')] type='ToolCallRequestEvent'
ToolCallExecutionEvent source='looped_assistant' models_usage=None metadata={} content=[FunctionExecutionResult(content='6', name='increment_number', call_id='call_qTDXSouN3MtGDqa8l0DM1ciD', is_error=False)] type='ToolCallExecutionEvent'
ToolCallSummaryMessage source='looped_assistant' models_usage=None metadata={} content='6' type='ToolCallSummaryMessage'
ToolCallRequestEvent source='looped_assistant' models_usage=RequestUsage(prompt_tokens=103, completion_tokens=15) metadata={} content=[FunctionCall(id='call_VGZPlsFVVdyxutR63Yr087pt', arguments='{"number":6}', name='increment_number')] type='ToolCallRequestEvent'
ToolCallExecutionEvent source='looped_assistant' models_usage=None metadata={} content=[FunctionExecutionResult(content='7', name='increment_number', call_id='call_VGZPlsFVVdyxutR63Yr087pt', is_error=False)] type='ToolCallExecutionEvent'
ToolCallSummaryMessage source='looped_assistant' models_usage=None metadata={} content='7' type='ToolCallSummaryMessage'
ToolCallRequestEvent source='looped_assistant' models_usage=RequestUsage(prompt_tokens=131, completion_tokens=15) metadata={} content=[FunctionCall(id='call_VRKGPqPM9AHoef2g2kgsKwZe', arguments='{"number":7}', name='increment_number')] type='ToolCallRequestEvent'
ToolCallExecutionEvent source='looped_assistant' models_usage=None metadata={} content=[FunctionExecutionResult(content='8', name='increment_number', call_id='call_VRKGPqPM9AHoef2g2kgsKwZe', is_error=False)] type='ToolCallExecutionEvent'
ToolCallSummaryMessage source='looped_assistant' models_usage=None metadata={} content='8' type='ToolCallSummaryMessage'
ToolCallRequestEvent source='looped_assistant' models_usage=RequestUsage(prompt_tokens=159, completion_tokens=15) metadata={} content=[FunctionCall(id='call_TOUMjSCG2kVdFcw2CMeb5DYX', arguments='{"number":8}', name='increment_number')] type='ToolCallRequestEvent'
ToolCallExecutionEvent source='looped_assistant' models_usage=None metadata={} content=[FunctionExecutionResult(content='9', name='increment_number', call_id='call_TOUMjSCG2kVdFcw2CMeb5DYX', is_error=False)] type='ToolCallExecutionEvent'
ToolCallSummaryMessage source='looped_assistant' models_usage=None metadata={} content='9' type='ToolCallSummaryMessage'
ToolCallRequestEvent source='looped_assistant' models_usage=RequestUsage(prompt_tokens=187, completion_tokens=15) metadata={} content=[FunctionCall(id='call_wjq7OO9Kf5YYurWGc5lsqttJ', arguments='{"number":9}', name='increment_number')] type='ToolCallRequestEvent'
ToolCallExecutionEvent source='looped_assistant' models_usage=None metadata={} content=[FunctionExecutionResult(content='10', name='increment_number', call_id='call_wjq7OO9Kf5YYurWGc5lsqttJ', is_error=False)] type='ToolCallExecutionEvent'
ToolCallSummaryMessage source='looped_assistant' models_usage=None metadata={} content='10' type='ToolCallSummaryMessage'
TextMessage source='looped_assistant' models_usage=RequestUsage(prompt_tokens=215, completion_tokens=15) metadata={} content='The number 5 incremented to 10 is 10.' type='TextMessage'
TaskResult TaskResult(messages=[TextMessage(source='user', models_usage=None, metadata={}, content='Increment the number 5 to 10.', type='TextMessage'), ToolCallRequestEvent(source='looped_assistant', models_usage=RequestUsage(prompt_tokens=75, completion_tokens=15), metadata={}, content=[FunctionCall(id='call_qTDXSouN3MtGDqa8l0DM1ciD', arguments='{"number":5}', name='increment_number')], type='ToolCallRequestEvent'), ToolCallExecutionEvent(source='looped_assistant', models_usage=None, metadata={}, content=[FunctionExecutionResult(content='6', name='increment_number', call_id='call_qTDXSouN3MtGDqa8l0DM1ciD', is_error=False)], type='ToolCallExecutionEvent'), ToolCallSummaryMessage(source='looped_assistant', models_usage=None, metadata={}, content='6', type='ToolCallSummaryMessage'), ToolCallRequestEvent(source='looped_assistant', models_usage=RequestUsage(prompt_tokens=103, completion_tokens=15), metadata={}, content=[FunctionCall(id='call_VGZPlsFVVdyxutR63Yr087pt', arguments='{"number":6}', name='increment_number')], type='ToolCallRequestEvent'), ToolCallExecutionEvent(source='looped_assistant', models_usage=None, metadata={}, content=[FunctionExecutionResult(content='7', name='increment_number', call_id='call_VGZPlsFVVdyxutR63Yr087pt', is_error=False)], type='ToolCallExecutionEvent'), ToolCallSummaryMessage(source='looped_assistant', models_usage=None, metadata={}, content='7', type='ToolCallSummaryMessage'), ToolCallRequestEvent(source='looped_assistant', models_usage=RequestUsage(prompt_tokens=131, completion_tokens=15), metadata={}, content=[FunctionCall(id='call_VRKGPqPM9AHoef2g2kgsKwZe', arguments='{"number":7}', name='increment_number')], type='ToolCallRequestEvent'), ToolCallExecutionEvent(source='looped_assistant', models_usage=None, metadata={}, content=[FunctionExecutionResult(content='8', name='increment_number', call_id='call_VRKGPqPM9AHoef2g2kgsKwZe', is_error=False)], type='ToolCallExecutionEvent'), ToolCallSummaryMessage(source='looped_assistant', models_usage=None, metadata={}, content='8', type='ToolCallSummaryMessage'), ToolCallRequestEvent(source='looped_assistant', models_usage=RequestUsage(prompt_tokens=159, completion_tokens=15), metadata={}, content=[FunctionCall(id='call_TOUMjSCG2kVdFcw2CMeb5DYX', arguments='{"number":8}', name='increment_number')], type='ToolCallRequestEvent'), ToolCallExecutionEvent(source='looped_assistant', models_usage=None, metadata={}, content=[FunctionExecutionResult(content='9', name='increment_number', call_id='call_TOUMjSCG2kVdFcw2CMeb5DYX', is_error=False)], type='ToolCallExecutionEvent'), ToolCallSummaryMessage(source='looped_assistant', models_usage=None, metadata={}, content='9', type='ToolCallSummaryMessage'), ToolCallRequestEvent(source='looped_assistant', models_usage=RequestUsage(prompt_tokens=187, completion_tokens=15), metadata={}, content=[FunctionCall(id='call_wjq7OO9Kf5YYurWGc5lsqttJ', arguments='{"number":9}', name='increment_number')], type='ToolCallRequestEvent'), ToolCallExecutionEvent(source='looped_assistant', models_usage=None, metadata={}, content=[FunctionExecutionResult(content='10', name='increment_number', call_id='call_wjq7OO9Kf5YYurWGc5lsqttJ', is_error=False)], type='ToolCallExecutionEvent'), ToolCallSummaryMessage(source='looped_assistant', models_usage=None, metadata={}, content='10', type='ToolCallSummaryMessage'), TextMessage(source='looped_assistant', models_usage=RequestUsage(prompt_tokens=215, completion_tokens=15), metadata={}, content='The number 5 incremented to 10 is 10.', type='TextMessage')], stop_reason="Text message received from 'looped_assistant'")
The key is to focus on the termination condition.
In this example, we use a TextMessageTermination condition
that stops the team when the agent stop producing ToolCallSummaryMessage .
The team will keep running until the agent produces a TextMessage with the final result.
You can also use other termination conditions to control the agent.
See Termination Conditions for more details.
previous
Agents
next
Human-in-the-Loop
On this page
Creating a Team
Running a Team
Observing a Team
Resetting a Team
Stopping a Team
Resuming a Team
Aborting a Team
Single-Agent Team
Edit on GitHub
Show Source
so the DOM is not blocked --
© Copyright 2024, Microsoft.
Privacy Policy | Consumer Health Privacy
Built with the PyData Sphinx Theme 0.16.0.
